# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class TailscaleTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("https_config.rb"), File.join(@root, "config/rails_dev.rb"))
    @rails_socket = TCPServer.new("127.0.0.1", 0)
    @vite_socket = TCPServer.new("127.0.0.1", 0)
  end

  def teardown
    @rails_socket&.close
    @vite_socket&.close
    super
  end

  def test_skips_existing_background_foreground_and_funnel_ports
    pid = start_tailscale({ "TEST_TAILSCALE_CONFIG" => fixture("tailscale-serve.json") })
    wait_until { output.include?("Ready:") }
    routes = events.select { |event| event["event"] == "serve_started" }

    assert_equal([8444, 8446], routes.map { |route| route.fetch("port") })
    assert_includes output, "Ready: https://laptop.example.ts.net:8444"
    assert_includes output, "js: https://laptop.example.ts.net:8446"
    finish(pid)
  end

  def test_two_runs_get_separate_origins_and_independent_cleanup
    first = start_tailscale
    wait_until(first) { output(first).include?("Ready:") }
    second = start_tailscale
    wait_until(second) { output(second).include?("Ready:") }

    assert_includes output(first), "Ready: https://laptop.example.ts.net\n"
    assert_includes output(second), "Ready: https://laptop.example.ts.net:8444"
    finish(first)

    assert_equal 2, active_routes.size
    finish(second)

    assert_empty active_routes
  end

  def test_list_shows_the_public_urls_for_each_endpoint
    pid = start_tailscale
    wait_until(pid) { output(pid).include?("Ready:") }
    listing = start_cli(arguments: ["list"])

    assert_equal 0, finish(listing, nil).exitstatus
    assert_includes output(listing), "https://laptop.example.ts.net"
    assert_includes output(listing), "https://laptop.example.ts.net:8443"
    finish(pid)
  end

  def test_an_erb_run_needs_only_one_https_route
    File.write(File.join(@root, "Procfile.dev"), "web: bin/rails server\n")
    File.write(File.join(@root, "config/rails_dev.rb"), <<~RUBY)
      RailsDev.configure do |config|
        config.http :web, port: #{@rails_socket.addr[1]}
      end
    RUBY
    pid = start_tailscale
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_equal 1, active_routes.size
    finish(pid)

    assert_empty active_routes
  end

  def test_routes_follow_all_declared_http_endpoints
    File.open(File.join(@root, "Procfile.dev"), "a") do |file|
      file.puts("api: env TEST_ROLE=api TEST_PORT_ENV=API_PORT ruby server.rb")
    end
    File.write(File.join(@root, "config/rails_dev.local.rb"), <<~RUBY)
      RailsDev.configure do |config|
        config.http :api, port: #{@vite_socket.addr[1]}, env: "API_PORT", readiness: "/health"
      end
    RUBY
    pid = start_tailscale
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_equal 3, active_routes.size
    assert_includes output(pid), "api: https://laptop.example.ts.net:8444"
    finish(pid)

    assert_empty active_routes
  end

  def test_a_failed_second_registration_stops_the_first_without_starting_web
    pid = start_tailscale({ "TEST_TAILSCALE_FAIL_PORT" => "8443" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "Access denied"
    assert_equal(1, events.count { |event| event["event"] == "serve_started" })
    assert_empty active_routes
    refute(events.any? { |event| event["event"] == "started" })
  end

  def test_a_rails_startup_failure_removes_sharing_routes
    pid = start_tailscale({ "TEST_FAIL_RAILS" => "1" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_empty active_routes
  end

  def test_losing_a_serve_process_stops_its_app
    pid = start_tailscale
    wait_until { output.include?("Ready:") }
    route = events.find { |event| event["event"] == "serve_started" }
    Process.kill("TERM", route.fetch("pid"))

    assert_equal 1, finish(pid, nil).exitstatus
    assert_empty active_routes
    refute_path_exists route.fetch("runtime")
  end

  def test_retries_a_serve_port_conflict
    pid = start_tailscale({ "TEST_TAILSCALE_CONFLICT" => "1" })
    wait_until { output.include?("Ready:") }

    assert_includes output, "selecting ports again"
    assert_equal [8443, 8444], active_routes.map { |path| JSON.parse(File.read(path)).fetch("port") }.sort
    finish(pid)

    assert_empty active_routes
  end

  def test_web_bind_retries_release_previous_serve_processes
    pid = start_tailscale({ "TEST_BIND_CONFLICT" => "1" })
    wait_until { output.include?("Ready:") }

    assert_equal(4, events.count { |event| event["event"] == "serve_started" })
    assert_equal 2, active_routes.size
    finish(pid)

    assert_empty active_routes
  end

  def test_disconnected_tailscale_fails_before_docker
    pid = start_tailscale({ "TEST_TAILSCALE_STATE" => "Stopped" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "Connect Tailscale"
    refute(events.any? { |event| event["event"] == "compose_up" })
  end

  def test_missing_https_capability_fails_before_docker
    pid = start_tailscale({ "TEST_TAILSCALE_NO_HTTPS" => "1" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "Enable HTTPS certificates"
    refute(events.any? { |event| event["event"] == "compose_up" })
  end

  def test_unreadable_serve_status_does_not_allocate_ports
    pid = start_tailscale({ "TEST_TAILSCALE_STATUS_ERROR" => "1" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "Cannot read Serve configuration"
    assert_empty active_routes
  end

  def test_sharing_is_off_without_the_flag
    FileUtils.cp(fixture("http_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    pid = start_tailscale({ "TEST_TAILSCALE_STATE" => "Stopped" }, arguments: [])
    wait_until { output.include?("Ready:") }

    refute(events.any? { |event| event["event"] == "tailscale_check" })
    assert_includes output, "Ready: http://127.0.0.1:"
    finish(pid)
  end

  def test_sharing_combines_with_app_integrations
    FileUtils.cp(fixture("integrations_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    pid = start_tailscale({ "TEST_PROCESS_COMMAND" => fixture("process.rb") },
                          arguments: %w[--with worker --tailscale])
    wait_until { output.include?("Ready:") }
    worker = events.find { |event| event["event"] == "process_started" }

    assert_equal "https://laptop.example.ts.net", worker.fetch("url")
    assert_equal "worker", worker.fetch("arguments").first
    finish(pid)
  end

  def test_serve_readiness_has_a_timeout
    FileUtils.cp(fixture("short_timeout_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    pid = start_tailscale({ "TEST_TAILSCALE_TIMEOUT" => "1" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output, "Startup timed out after 1s."
    assert_includes output, "tailscale-web: readiness message not received"
    assert_empty active_routes
  end

  def test_interrupting_serve_startup_removes_its_route
    pid = start_tailscale({ "TEST_TAILSCALE_TIMEOUT" => "1" })
    wait_until { active_routes.any? }

    assert_equal 130, finish(pid).exitstatus
    assert_empty active_routes
  end

  private

  def start_tailscale(env = {}, arguments: ["--tailscale"])
    start_cli({ "TEST_RAILS_PORT" => @rails_socket.addr[1].to_s,
                "TEST_VITE_PORT" => @vite_socket.addr[1].to_s }.merge(env),
              arguments: ["start", "--root", @root, *arguments])
  end

  def active_routes
    Dir[File.join(@workspace, "tailscale/*.json")]
  end
end
