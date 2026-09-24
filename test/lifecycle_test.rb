# frozen_string_literal: true

require "test_helper"
require "net/http"
require "pty"
require_relative "support/cli_process"

class LifecycleTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("hooks_config.rb"), File.join(@root, "config/rails_dev.rb"))
    @rails_socket = TCPServer.new("127.0.0.1", 0)
    @vite_socket = TCPServer.new("127.0.0.1", 0)
  end

  def teardown
    super
  ensure
    @rails_socket&.close
    @vite_socket&.close
  end

  def test_hooks_wrap_preparation_startup_and_shutdown
    pid = start_with_hooks({}, prepare: true)
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_equal 130, finish(pid).exitstatus
    assert_equal %w[around_enter before_start after_ready around_exit after_stop], hook_names(pid)
    before = events.index { |event| event["name"] == "before_start" }
    prepare = events.index { |event| event["event"] == "task" }
    stopped = events.rindex { |event| event["event"] == "stopped" }
    around_exit = events.index { |event| event["name"] == "around_exit" }

    assert_operator before, :<, prepare
    assert_operator stopped, :<, around_exit
  end

  def test_ready_hooks_receive_the_selected_urls_and_connections
    pid = start_with_hooks
    wait_until(pid) { output(pid).include?("Ready:") }
    ready = hooks(pid).find { |event| event["name"] == "after_ready" }
    body = JSON.parse(Net::HTTP.get(URI(ready.fetch("url"))))

    assert_equal "45432", ready.fetch("pgport")
    assert_equal body.fetch("vite_url"), ready.fetch("vite_url")
    assert_equal @root, ready.fetch("root")
    assert_equal ready.fetch("runtime"), body.fetch("runtime")
    finish(pid)
  end

  def test_stop_hooks_can_run_commands_after_an_interrupt_before_runtime_removal
    pid = start_with_hooks
    wait_until(pid) { output(pid).include?("Ready:") }
    finish(pid)
    stopped = hooks(pid).last
    command = events.find { |event| event["event"] == "hook_command" && event["name"] == "after_stop" }

    assert stopped.fetch("runtime_exists")
    assert_equal "45432", command.fetch("pgport")
    assert_equal @root, command.fetch("root")
    refute_path_exists stopped.fetch("runtime")
  end

  def test_hangup_stops_the_servers_and_runs_cleanup
    pid = start_with_hooks
    ready_response(pid)

    assert_equal 129, finish(pid, "HUP").exitstatus
    assert_equal "after_stop", hook_names(pid).last
    refute_path_exists hooks(pid).last.fetch("runtime")
  end

  def test_cleanup_completes_when_the_terminal_has_closed
    PTY.open do |reader, writer|
      pid = start_with_hooks({}, terminal: writer)
      writer.close
      wait_until(pid) { hooks(pid).any? { |event| event["name"] == "after_ready" } }
      reader.close

      assert_equal 129, finish(pid, "HUP").exitstatus
      assert_equal "after_stop", hook_names(pid).last
      refute_path_exists hooks(pid).last.fetch("runtime")
      refute_includes output(pid), "Errno::EIO"
    end
  end

  def test_before_start_failure_aborts_startup_and_runs_cleanup
    pid = start_with_hooks({ "TEST_FAIL_HOOK" => "before_start" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "before_start hook failed: before_start failed"
    assert_equal %w[around_enter before_start around_exit after_stop], hook_names(pid)
    refute(events.any? { |event| event["event"] == "started" })
    refute_path_exists hooks(pid).last.fetch("runtime")
  end

  def test_environment_failure_still_runs_stop_hooks_with_partial_context
    pid = start_with_hooks({ "DATABASE_URL" => "postgres://example.invalid/database" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_equal ["after_stop"], hook_names(pid)
    assert_nil hooks(pid).last.fetch("url")
    assert_includes hooks(pid).last.fetch("error"), "Unset DATABASE_URL"
    refute_path_exists hooks(pid).last.fetch("runtime")
  end

  def test_after_ready_failure_stops_the_started_servers
    pid = start_with_hooks({ "TEST_FAIL_HOOK" => "after_ready" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "after_ready hook failed: after_ready failed"
    events.select { |event| event["event"] == "started" }.each do |event|
      assert_raises(Errno::ESRCH) { Process.kill(0, event.fetch("pid")) }
    end
    refute_path_exists hooks(pid).last.fetch("runtime")
  end

  def test_startup_failure_is_preserved_when_a_stop_hook_also_fails
    pid = start_with_hooks({ "TEST_FAIL_RAILS" => "1", "TEST_FAIL_HOOK" => "after_stop" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "after_stop hook failed: after_stop failed"
    assert_includes output(pid), "rails-dev: foreman exited during startup"
    refute_path_exists hooks(pid).last.fetch("runtime")
  end

  def test_a_handled_startup_error_still_cleans_up_the_run
    FileUtils.cp(fixture("rescuing_around_hook.rb"), File.join(@root, "config/rails_dev.local.rb"))
    pid = start_with_hooks({ "TEST_FAIL_HOOK" => "before_start" })

    assert_equal 0, finish(pid, nil).exitstatus
    assert_equal %w[around_enter before_start around_exit after_stop], hook_names(pid)
    assert_nil hooks(pid).last.fetch("error")
    refute_path_exists hooks(pid).last.fetch("runtime")
  end

  def test_a_failing_around_ensure_still_runs_stop_hooks_and_removes_runtime
    pid = start_with_hooks({ "TEST_FAIL_HOOK" => "around_exit" })
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_equal 1, finish(pid).exitstatus
    assert_includes output(pid), "around_run hook failed: around_exit failed"
    assert_equal "around_run hook failed: around_exit failed", hooks(pid).last.fetch("error")
    refute_path_exists hooks(pid).last.fetch("runtime")
  end

  def test_interrupts_a_running_hook_command_and_still_runs_cleanup
    gate = File.join(@workspace, "hook.gate")
    File.write(gate, "")
    pid = start_with_hooks({ "TEST_HOOK_GATE_AT" => "before_start", "TEST_HOOK_GATE" => gate })
    wait_until(pid) { events.any? { |event| event["event"] == "hook_command" } }

    assert_equal 143, finish(pid, "TERM").exitstatus
    assert_equal %w[around_enter before_start around_exit after_stop], hook_names(pid)
    assert(events.any? { |event| event["event"] == "hook_command" && event["name"] == "after_stop" })
    command = events.find { |event| event["event"] == "hook_command" }

    assert_raises(Errno::ESRCH) { Process.kill(0, command.fetch("pid")) }
  end

  def test_ready_hooks_do_not_block_another_instances_startup_or_cleanup
    gate = File.join(@workspace, "hook.gate")
    File.write(gate, "")
    first = start_with_hooks({ "TEST_HOOK_GATE_AT" => "after_ready", "TEST_HOOK_GATE" => gate })
    wait_until(first) { events.any? { |event| event["event"] == "hook_command" && event["name"] == "after_ready" } }
    second = start_with_hooks
    wait_until(second) { output(second).include?("Ready:") }
    first_runtime = hooks(first).first.fetch("runtime")
    second_ready = hooks(second).find { |event| event["name"] == "after_ready" }
    finish(first)

    refute_path_exists first_runtime
    assert_path_exists second_ready.fetch("runtime")
    assert_equal "200", Net::HTTP.get_response(URI(second_ready.fetch("url"))).code
    finish(second)

    assert_equal 1, hook_names(second).count("after_stop")
  end

  def test_before_hooks_are_serialized_and_a_waiting_run_can_be_cancelled
    gate = File.join(@workspace, "hook.gate")
    File.write(gate, "")
    first = start_with_hooks({ "TEST_HOOK_GATE_AT" => "before_start", "TEST_HOOK_GATE" => gate })
    wait_until(first) { events.any? { |event| event["event"] == "hook_command" } }
    second = start_with_hooks
    wait_until(second) { hook_names(second).include?("around_enter") }

    assert_equal 143, finish(second, "TERM").exitstatus
    assert_equal %w[around_enter around_exit after_stop], hook_names(second)
    File.unlink(gate)
    wait_until(first) { output(first).include?("Ready:") }

    assert_equal 130, finish(first).exitstatus
  end

  def test_a_server_exit_interrupts_a_running_ready_hook_command
    gate = File.join(@workspace, "hook.gate")
    File.write(gate, "")
    pid = start_with_hooks({ "TEST_HOOK_GATE_AT" => "after_ready", "TEST_HOOK_GATE" => gate })
    wait_until(pid) { events.any? { |event| event["event"] == "hook_command" && event["name"] == "after_ready" } }
    vite = events.find { |event| event["event"] == "started" && event["role"] == "vite" }
    Process.kill("TERM", vite.fetch("pid"))

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "foreman exited while running"
    assert_equal "after_stop", hook_names(pid).last
    refute_path_exists hooks(pid).last.fetch("runtime")
  end

  def test_bind_retries_do_not_repeat_lifecycle_hooks
    pid = start_with_hooks({ "TEST_BIND_CONFLICT" => "1" })
    wait_until(pid) { output(pid).include?("Ready:") }
    finish(pid)

    assert_includes output(pid), "selecting ports again"
    assert_equal %w[around_enter before_start after_ready around_exit after_stop], hook_names(pid)
  end

  private

  def start_with_hooks(env = {}, prepare: false, terminal: nil)
    start_cli({ "TEST_RAILS_PORT" => @rails_socket.addr[1].to_s, "TEST_VITE_PORT" => @vite_socket.addr[1].to_s,
                "TEST_HOOK_COMMAND" => fixture("hook_command.rb") }.merge(env), prepare: prepare, terminal: terminal)
  end

  def hooks(pid)
    events.select { |event| event["event"] == "hook" && event["pid"] == pid }
  end

  def hook_names(pid)
    hooks(pid).map { |event| event.fetch("name") }
  end
end
