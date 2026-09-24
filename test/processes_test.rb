# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class ProcessesTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("process_config.rb"), File.join(@root, "config/rails_dev.rb"))
    FileUtils.cp(fixture("process_hook.rb"), File.join(@root, "config/rails_dev.local.rb"))
    @rails_socket = TCPServer.new("127.0.0.1", 0)
    @vite_socket = TCPServer.new("127.0.0.1", 0)
  end

  def teardown
    super
  ensure
    @rails_socket&.close
    @vite_socket&.close
  end

  def test_process_inherits_the_run_environment_and_literal_arguments
    pid = start_with_processes
    response = ready_response(pid)
    process = events.find { |event| event["event"] == "process_started" }

    assert_equal ["two words; $(not-a-command)"], process.fetch("arguments")
    assert_equal @root, process.fetch("root")
    assert_equal "45432", process.fetch("pgport")
    assert_equal response.fetch("runtime"), process.fetch("runtime")
    assert_equal response.fetch("rails_port"), process.fetch("rails_port")
    finish(pid)
  end

  def test_processes_without_a_readiness_message_are_accepted_when_running
    pid = start_with_processes({ "TEST_PROCESS_NO_MARKER" => "1" })
    ready_response(pid)
    wait_until(pid) { events.any? { |event| event["event"] == "process_started" } }

    assert_equal 130, finish(pid).exitstatus
    assert(events.any? { |event| event["event"] == "process_stopped" })
  end

  def test_interrupt_stops_extra_processes_and_their_descendants
    pid = start_with_processes({ "TEST_PROCESS_TREE" => "1" })
    response = ready_response(pid)
    descendant = events.find { |event| event["event"] == "process_descendant" }.fetch("descendant")

    assert_equal 130, finish(pid).exitstatus
    assert_raises(Errno::ESRCH) { Process.kill(0, descendant) }
    refute_path_exists response.fetch("runtime")
  end

  def test_interrupt_stops_a_worker_that_has_not_printed_a_ready_message
    gate = File.join(@workspace, "process.gate")
    File.write(gate, "")
    pid = start_with_processes({ "TEST_PROCESS_GATE" => gate })
    worker = wait_until(pid) { events.find { |event| event["event"] == "process_started" } }

    assert_equal 130, finish(pid).exitstatus
    assert_raises(Errno::ESRCH) { Process.kill(0, worker.fetch("pid")) }
    refute_path_exists worker.fetch("runtime")
  end

  def test_extra_process_exit_stops_the_whole_run
    pid = start_with_processes
    response = ready_response(pid)
    worker = events.find { |event| event["event"] == "process_started" }
    Process.kill("TERM", worker.fetch("pid"))

    assert_equal 0, finish(pid, nil).exitstatus
    assert_match(/worker\.1\s+\| exited with code 0/, output(pid))
    events.select { |event| event["event"] == "started" }.each do |event|
      assert_raises(Errno::ESRCH) { Process.kill(0, event.fetch("pid")) }
    end
    refute_path_exists response.fetch("runtime")
  end

  def test_rails_exit_stops_extra_processes
    pid = start_with_processes
    ready_response(pid)
    rails = events.find { |event| event["event"] == "started" && event["role"] == "rails" }
    worker = events.find { |event| event["event"] == "process_started" }
    Process.kill("TERM", rails.fetch("pid"))

    assert_equal 0, finish(pid, nil).exitstatus
    assert_raises(Errno::ESRCH) { Process.kill(0, worker.fetch("pid")) }
  end

  def test_failed_extra_process_does_not_retry_rails_ports
    pid = start_with_processes({ "TEST_PROCESS_FAIL" => "1" })

    assert_equal 23, finish(pid, nil).exitstatus
    assert_includes output(pid), "foreman exited during startup"
    refute_includes output(pid), "selecting ports again"
  end

  def test_later_hook_failure_stops_an_already_started_process
    pid = start_with_processes({ "TEST_FAIL_AFTER_PROCESS" => "1" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "Hook failed after starting a process"
    worker = events.find { |event| event["event"] == "process_started" }

    assert_raises(Errno::ESRCH) { Process.kill(0, worker.fetch("pid")) }
  end

  def test_stopping_one_run_preserves_another_runs_extra_process
    first = start_with_processes
    first_response = ready_response(first)
    second = start_with_processes
    second_response = ready_response(second)
    second_worker = events.find do |event|
      event["event"] == "process_started" && event["runtime"] == second_response.fetch("runtime")
    end
    finish(first)

    refute_path_exists first_response.fetch("runtime")
    assert_equal 1, Process.kill(0, second_worker.fetch("pid"))
    assert_equal second_response, ready_response(second)
    finish(second)
  end

  def test_multiple_extra_processes_are_supervised
    pid = start_with_processes({ "TEST_TWO_PROCESSES" => "1" })
    ready_response(pid)
    wait_until(pid) { events.count { |event| event["event"] == "process_started" } == 2 }
    workers = events.select { |event| event["event"] == "process_started" }
    Process.kill("TERM", workers.last.fetch("pid"))

    assert_equal 0, finish(pid, nil).exitstatus
    workers.each { |worker| assert_raises(Errno::ESRCH) { Process.kill(0, worker.fetch("pid")) } }
  end

  private

  def start_with_processes(env = {})
    start_cli({ "TEST_RAILS_PORT" => @rails_socket.addr[1].to_s, "TEST_VITE_PORT" => @vite_socket.addr[1].to_s,
                "TEST_PROCESS_COMMAND" => fixture("process.rb") }.merge(env))
  end
end
