# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class StopTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    @state = RailsDev::State.new(base: @workspace)
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("hooks_config.rb"), File.join(@root, "config/rails_dev.rb"))
    @rails_socket = TCPServer.new("127.0.0.1", 0)
    @vite_socket = TCPServer.new("127.0.0.1", 0)
    @owned_groups = []
  end

  def teardown
    super
  ensure
    @rails_socket&.close
    @vite_socket&.close
  end

  def test_stopping_a_live_instance_runs_its_hooks_and_preserves_the_other_instance
    first = start_app
    first_response = ready_response(first)
    second = start_app
    second_response = ready_response(second)
    stop_instance(first_response.fetch("runtime"))

    assert_equal 143, finish(first, nil).exitstatus
    assert(events.any? { |event| event["pid"] == first && event["name"] == "after_stop" })
    assert_equal "200", Net::HTTP.get_response(URI("http://127.0.0.1:#{second_response.fetch("rails_port")}")).code
    refute(events.any? { |event| event["event"] == "compose_stop" })
    finish(second)
  end

  def test_recovers_an_orphan_without_loading_app_configuration
    pid = start_app
    runtime = ready_response(pid).fetch("runtime")
    remember_groups(runtime)
    kill_launcher(pid, runtime)
    File.write(File.join(@root, "config/rails_dev.rb"), 'raise "Do not load app configuration"')

    assert_equal "orphaned", @state.runs.fetch(0).fetch("status")
    stop_instance(runtime)

    refute_path_exists runtime
    assert_empty @state.runs
    refute(events.any? { |event| event["event"] == "compose_stop" })
  end

  def test_recovers_a_preparation_command_before_servers_start
    gate = File.join(@workspace, "prepare.gate")
    File.write(gate, "")
    pid = start_app("TEST_HOOK_GATE_AT" => "before_start", "TEST_HOOK_GATE" => gate)
    command = wait_until(pid) { events.find { |event| event["event"] == "hook_command" } }
    runtime = command.fetch("runtime")
    remember_groups(runtime)
    kill_launcher(pid, runtime)
    stop_instance(runtime)

    refute_path_exists runtime
    refute RailsDev::ProcessTable.new.identity(command.fetch("pid"))
    refute(events.any? { |event| event["event"] == "started" })
  end

  def test_recovery_preserves_another_orphan_from_the_same_checkout
    first = start_app
    first_runtime = ready_response(first).fetch("runtime")
    second = start_app
    second_response = ready_response(second)
    remember_groups(first_runtime)
    remember_groups(second_response.fetch("runtime"))
    kill_launcher(first, first_runtime)
    kill_launcher(second, second_response.fetch("runtime"))
    stop_instance(first_runtime)

    assert_equal "200", Net::HTTP.get_response(URI("http://127.0.0.1:#{second_response.fetch("rails_port")}")).code
    assert_equal([second], @state.runs.map { |run| run.fetch("pid") })
    stop_instance(second_response.fetch("runtime"))
  end

  def test_recovers_servers_after_foreman_has_also_been_killed
    pid = start_app
    runtime = ready_response(pid).fetch("runtime")
    remember_groups(runtime)
    kill_launcher(pid, runtime)
    Process.kill("KILL", @owned_groups.fetch(0))
    stop_instance(runtime)

    assert_empty RailsDev::ProcessTable.new.members(@owned_groups)
    refute_path_exists runtime
  end

  def test_rejects_a_process_whose_recorded_start_time_does_not_match
    pid = start_app
    runtime = ready_response(pid).fetch("runtime")
    remember_groups(runtime)
    kill_launcher(pid, runtime)
    instance = RailsDev::Instance.new(runtime)
    details = JSON.parse(File.read(File.join(runtime, "instance.json")))
    records = details.fetch("processes").map { |process| [*process.take(2), "different start time"] }
    instance.record(processes: records)
    stopper = start_cli(arguments: ["stop", File.basename(runtime)])

    assert_equal 1, finish(stopper, nil).exitstatus
    assert_includes output(stopper), "Cannot verify process groups #{@owned_groups.join(", ")}"
    assert_path_exists runtime
    assert_equal "interrupted", @state.runs.fetch(0).fetch("status")
    assert_includes output(stopper), "Inspect #{File.join(runtime, "instance.json")}"
  end

  def test_refuses_to_signal_a_launcher_with_a_different_identity
    pid = start_app
    runtime = ready_response(pid).fetch("runtime")
    instance = RailsDev::Instance.new(runtime)
    instance.record(owner: [pid, Process.getpgid(pid), "different start time"])
    stopper = start_cli(arguments: ["stop", File.basename(runtime)])

    assert_equal 1, finish(stopper, nil).exitstatus
    assert_includes output(stopper), "Cannot verify the launcher for #{File.basename(runtime)} (PID #{pid})"
    assert RailsDev::ProcessTable.new.identity(pid)
    finish(pid)
  end

  def test_escalates_when_the_live_launcher_cannot_respond
    pid = start_app
    runtime = ready_response(pid).fetch("runtime")
    Process.kill("STOP", pid)
    details = JSON.parse(File.read(File.join(runtime, "instance.json")))
    (@abandoned ||= []).concat(details.fetch("processes"))
    RailsDev::Instance.new(runtime).record(shutdown_timeout: 0.1)
    stop_instance(runtime)

    assert_equal Signal.list.fetch("KILL"), finish(pid, nil).termsig
    refute_path_exists runtime
  ensure
    Process.kill("CONT", pid) if pid && RailsDev::ProcessTable.new.identity(pid)
  end

  def test_rejects_unknown_instance_ids
    pid = start_cli(arguments: %w[stop missing])

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "Unknown instance"
    refute_path_exists @state.directory
  end

  private

  def start_app(env = {})
    start_cli({ "TEST_RAILS_PORT" => @rails_socket.addr[1].to_s,
                "TEST_VITE_PORT" => @vite_socket.addr[1].to_s,
                "TEST_HOOK_COMMAND" => fixture("hook_command.rb") }.merge(env))
  end

  def remember_groups(runtime)
    details = wait_until do
      recorded = JSON.parse(File.read(File.join(runtime, "instance.json")))
      recorded unless recorded.fetch("processes").empty?
    end
    @owned_groups.concat(details.fetch("processes").map { |process| process[1] }.uniq)
  end

  def stop_instance(runtime)
    pid = start_cli(arguments: ["stop", File.basename(runtime)])

    assert_equal 0, finish(pid, nil).exitstatus, output(pid)
  end
end
