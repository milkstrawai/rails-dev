# frozen_string_literal: true

require "test_helper"
require "net/http"
require_relative "support/cli_process"

class CLITest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    File.chmod(0o755, File.join(@root, "bin/rails"))
    FileUtils.mkdir_p(File.join(@root, "config"))
    @rails_socket = TCPServer.new("127.0.0.1", 0)
    @vite_socket = TCPServer.new("127.0.0.1", 0)
    File.write(File.join(@root, "config/rails_dev.rb"), <<~RUBY)
      RailsDev.configure do |config|
        config.https = false
        config.integrations << :prepare
        config.before_start do |run|
          next unless run.enabled?(:prepare)

          %w[deps:ruby deps:js db:prepare].each { |task| run.run("mise", "run", task) }
        end
        config.compose_file = "dev-docker-compose.yml"
        config.connect "postgres", port: 5432, env: { "PGHOST" => "%{host}", "PGPORT" => "%{port}" }
        config.http :web, port: #{@rails_socket.addr[1]}
        config.http :js, port: #{@vite_socket.addr[1]}, env: "VITE_PORT", url_env: "RAILS_DEV_VITE_URL", readiness: "/@vite/client"
      end
    RUBY
  end

  def teardown
    @rails_socket&.close
    @vite_socket&.close
    super
  end

  def test_starts_on_free_ports_and_stops_both_servers_on_interrupt
    pid = start_cli
    wait_until { output.include?("Ready:") }
    started = events.select { |event| event["event"] == "started" }

    assert_operator started.find { |event| event["role"] == "rails" }.fetch("port"), :>, @rails_socket.addr[1]
    assert_operator started.find { |event| event["role"] == "vite" }.fetch("port"), :>, @vite_socket.addr[1]
    assert_equal 130, finish(pid).exitstatus
    stopped = events.select { |event| event["event"] == "stopped" }

    assert_equal %w[rails vite], stopped.map { |event| event["role"] }.sort
  end

  def test_uses_dynamic_compose_ports_without_recreating_shared_services
    pid = start_cli
    wait_until { output.include?("Ready:") }
    invocation = events.find { |event| event["event"] == "compose_up" }

    assert_includes invocation.fetch("arguments"), "--no-recreate"
    assert_includes invocation.fetch("override"), "ports: !override"
    refute_includes invocation.fetch("override"), "5434"
    assert_equal File.join(@root, "dev-docker-compose.yml"), invocation.fetch("base")
    finish(pid)
  end

  def test_runs_only_app_requested_preparation_with_discovered_connections
    pid = start_cli({}, prepare: true)
    wait_until { output.include?("Ready:") }
    tasks = events.select { |event| event["event"] == "task" }

    assert_equal(%w[deps:ruby deps:js db:prepare], tasks.map { |event| event["name"] })
    assert_equal "45432", tasks.last.fetch("port")
    finish(pid)
  end

  def test_cleans_up_when_vite_fails_without_retrying_an_application_error
    pid = start_cli({ "TEST_FAIL_VITE" => "1" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "exited during startup"
    refute_includes output, "selecting ports again"
    remaining = events.select { |event| event["event"] == "started" }.reject do |started|
      events.any? { |event| event["event"] == "stopped" && event["pid"] == started["pid"] }
    end

    assert_empty remaining
  end

  def test_retries_an_actual_bind_error
    pid = start_cli({ "TEST_BIND_CONFLICT" => "1" })
    wait_until { output.include?("Ready:") }

    assert_includes output, "selecting ports again"
    finish(pid)
  end

  def test_starts_two_runs_with_their_own_vite_servers_and_pid_files
    first = start_cli
    second = start_cli
    first_response = ready_response(first)
    second_response = ready_response(second)

    refute_equal first_response.fetch("rails_port"), second_response.fetch("rails_port")
    refute_equal first_response.fetch("vite_url"), second_response.fetch("vite_url")
    rails = events.select { |event| event["event"] == "started" && event["role"] == "rails" }

    assert_equal 2, rails.map { |event| event.fetch("pidfile") }.uniq.size
    rails.each { |event| assert_equal event.fetch("pid").to_s, File.read(event.fetch("pidfile")) }
    finish(first)
    finish(second)
  end

  def test_stopping_one_run_preserves_the_other_runs_metadata_and_server
    first = start_cli
    first_response = ready_response(first)
    second = start_cli
    second_response = ready_response(second)
    finish(first)

    refute_path_exists first_response.fetch("runtime")
    assert_equal second_response, ready_response(second)
    assert_path_exists File.join(second_response.fetch("runtime"), "rails-vite.json")
    finish(second)

    refute_path_exists second_response.fetch("runtime")
  end

  def test_failure_in_a_second_run_does_not_stop_the_first
    first = start_cli
    first_response = ready_response(first)
    second = start_cli({ "TEST_FAIL_VITE" => "1" })

    assert_equal 1, finish(second, nil).exitstatus
    assert_equal first_response, ready_response(first)
    assert_path_exists File.join(first_response.fetch("runtime"), "rails-vite.json")
    finish(first)
  end

  def test_serializes_preparation_for_simultaneous_starts
    gate = File.join(@workspace, "prepare.gate")
    File.write(gate, "")
    first = start_cli({ "TEST_PREPARE_GATE" => gate }, prepare: true)
    wait_until(first) { events.any? { |event| event["event"] == "task" } }
    second = start_cli({}, prepare: true)
    wait_until(second) { Dir.glob(File.join(@workspace, "rails-dev/run-*")).size == 2 }
    File.unlink(gate)
    first_response = ready_response(first)
    ready_response(second)
    tasks = events.select { |event| event["event"] == "task" }
    groups = tasks.chunk { |event| event.fetch("runtime") }.to_a

    assert_equal 2, groups.size
    assert_equal first_response.fetch("runtime"), groups.first.first
    groups.map(&:last).each do |group|
      assert_equal(%w[deps:ruby deps:js db:prepare], group.map { |event| event.fetch("name") })
    end
    finish(first)
    finish(second)
  end

  def test_rails_startup_failure_cleans_up_its_vite_without_stopping_another_run
    first = start_cli
    first_response = ready_response(first)
    second = start_cli({ "TEST_FAIL_RAILS" => "1" })

    assert_equal 1, finish(second, nil).exitstatus
    vite = events.find do |event|
      event["event"] == "started" && event["role"] == "vite" && event["runtime"] != first_response.fetch("runtime")
    end

    assert_raises(Errno::ESRCH) { Process.kill(0, vite.fetch("pid")) }
    refute_path_exists vite.fetch("runtime")
    assert_equal first_response, ready_response(first)
    response = JSON.parse(Net::HTTP.get(URI(first_response.fetch("vite_url"))))

    assert_equal "vite", response.fetch("role")
    finish(first)
  end

  def test_interrupts_a_waiting_run_without_interrupting_preparation
    gate = File.join(@workspace, "prepare.gate")
    File.write(gate, "")
    first = start_cli({ "TEST_PREPARE_GATE" => gate }, prepare: true)
    wait_until(first) { events.any? { |event| event["event"] == "task" } }
    second = start_cli({}, prepare: true)
    wait_until(second) { Dir.glob(File.join(@workspace, "rails-dev/run-*")).size == 2 }

    assert_equal 143, finish(second, "TERM").exitstatus
    assert_equal(1, events.count { |event| event["event"] == "task" })
    File.unlink(gate)
    ready_response(first)

    assert_equal 130, finish(first).exitstatus
  end

  def test_does_not_start_app_processes_when_preparation_fails
    pid = start_cli({ "TEST_FAIL_PREPARE" => "1" }, prepare: true)

    assert_equal 1, finish(pid, nil).exitstatus
    refute(events.any? { |event| event["event"] == "started" })
  end

  def test_passes_the_discovered_database_port_to_the_running_app
    pid = start_cli
    wait_until { output.include?("Ready:") }
    url = output.match(%r{Ready: (http://127\.0\.0\.1:\d+)})[1]
    response = JSON.parse(Net::HTTP.get(URI(url)))

    assert_equal "45432", response.fetch("pgport")
    finish(pid)
  end

  def test_stops_the_other_server_when_a_running_child_exits
    pid = start_cli
    wait_until { output.include?("Ready:") }
    vite = events.find { |event| event["event"] == "started" && event["role"] == "vite" }
    Process.kill("TERM", vite.fetch("pid"))

    assert_equal 0, finish(pid, nil).exitstatus
    assert_includes output, "sending SIGTERM"
    assert(events.any? { |event| event["event"] == "stopped" && event["role"] == "rails" })
  end

  def test_can_be_terminated_during_preparation
    pid = start_cli({ "TEST_BLOCK_PREPARE" => "1" }, prepare: true)
    wait_until { events.any? { |event| event["event"] == "task" } }

    assert_equal 143, finish(pid, "TERM").exitstatus
    refute(events.any? { |event| event["event"] == "started" })
  end

  def test_rejects_an_external_database_url_before_starting_services
    pid = start_cli({ "DATABASE_URL" => "postgres://example.invalid/database" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "Unset DATABASE_URL"
    assert_empty events
  end

  def test_rejects_compose_versions_without_port_replacement
    pid = start_cli({ "TEST_COMPOSE_VERSION" => "2.24.3" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "2.24.4 or newer"
    assert_empty events
  end

  def test_rejects_a_postgres_endpoint_exposed_beyond_loopback
    pid = start_cli({ "TEST_PGHOST" => "0.0.0.0" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "must publish one port on 127.0.0.1"
    refute(events.any? { |event| event["event"] == "started" })
  end

  def test_detects_an_existing_rails_server_before_preparation
    FileUtils.mkdir_p(File.join(@root, "tmp/pids"))
    File.write(File.join(@root, "tmp/pids/server.pid"), Process.pid.to_s)
    pid = start_cli({}, prepare: true)

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "Rails is already running"
    assert_empty events
  end

  def test_readiness_survives_verbose_startup_output
    pid = start_cli({ "TEST_VERBOSE_STARTUP" => "1" })
    wait_until { output.include?("Ready:") }

    assert_equal 130, finish(pid).exitstatus
  end

  def test_rejects_an_additional_binding_on_an_existing_container
    pid = start_cli({ "TEST_EXTRA_BINDING" => "1" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "must publish one port on 127.0.0.1"
    refute(events.any? { |event| event["event"] == "started" })
  end
end
