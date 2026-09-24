# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class IntegrationsTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("process_config.rb"), File.join(@root, "config/rails_dev.rb"))
    FileUtils.cp(fixture("integrations_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    @rails_socket = TCPServer.new("127.0.0.1", 0)
    @vite_socket = TCPServer.new("127.0.0.1", 0)
  end

  def teardown
    super
  ensure
    @rails_socket&.close
    @vite_socket&.close
  end

  def test_integrations_are_off_without_with
    pid = start_with
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_empty workers
    finish(pid)
  end

  def test_selection_is_available_before_start_and_after_readiness
    pid = start_with("worker")
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_equal(["worker"], workers.map { |worker| worker.fetch("name") })
    assert_equal ["worker"], workers.first.fetch("arguments")
    finish(pid)
  end

  def test_multiple_names_enable_multiple_integrations
    pid = start_with("worker", "helper")
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_equal %w[helper worker], workers.map { |worker| worker.fetch("name") }.sort
    finish(pid)
  end

  def test_unknown_names_fail_before_docker_or_hooks
    pid = start_with("worker", "typo")

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "Unknown integrations: typo"
    assert_includes output(pid), "Available integrations: worker, helper"
    assert_empty events
  end

  def test_no_integrations_are_builtin
    File.unlink(File.join(@root, "config/rails_dev.local.rb"))
    pid = start_with("stripe")

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "Available integrations: none"
    assert_empty events
  end

  def test_concurrent_runs_keep_their_own_selection
    first = start_with("worker")
    wait_until(first) { output(first).include?("Ready:") }
    second = start_with("helper")
    wait_until(second) { output(second).include?("Ready:") }
    helper = workers.find { |worker| worker.fetch("name") == "helper" }
    finish(first)

    assert_equal ["none"], helper.fetch("arguments")
    assert_equal 1, Process.kill(0, helper.fetch("pid"))
    finish(second)
  end

  private

  def start_with(*integrations)
    arguments = ["start", "--root", @root]
    arguments += ["--with", *integrations] unless integrations.empty?
    start_cli({ "TEST_RAILS_PORT" => @rails_socket.addr[1].to_s, "TEST_VITE_PORT" => @vite_socket.addr[1].to_s,
                "TEST_PROCESS_COMMAND" => fixture("process.rb") },
              arguments: arguments)
  end

  def workers
    events.select { |event| event["event"] == "process_started" }
  end
end
