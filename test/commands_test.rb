# frozen_string_literal: true

require "test_helper"
require "rbconfig"

class CommandsTest < Minitest::Test
  include TestWorkspace

  def setup
    super
    @commands = RailsDev::Commands.new(@root, output: StringIO.new)
  end

  def teardown
    @commands.stop
    super
  end

  def test_keeps_capture_stdout_separate_from_stderr
    result = @commands.capture(RbConfig.ruby, fixture("worker.rb"), "capture", "two words; $(false)")

    assert_equal "two words; $(false)", JSON.parse(result).fetch("argument")
  end

  def test_does_not_pass_the_launcher_bundle_to_the_app
    result = @commands.capture(RbConfig.ruby, fixture("worker.rb"), "capture", "argument")

    assert_nil JSON.parse(result).fetch("bundle")
  end

  def test_propagates_command_failure
    error = assert_raises(RailsDev::Error) do
      @commands.run(RbConfig.ruby, fixture("worker.rb"), "failure")
    end

    assert_match(/database is unavailable/, error.message)
  end

  def test_reports_the_signal_that_terminated_a_command_without_echoing_arguments
    error = assert_raises(RailsDev::Error) do
      @commands.capture(RbConfig.ruby, fixture("worker.rb"), "terminated", "private-argument")
    end

    assert_equal "#{RbConfig.ruby} failed (signal TERM).", error.message
    refute_includes error.message, "private-argument"
  end

  def test_reports_captured_failures_written_only_to_stdout
    error = assert_raises(RailsDev::Error) do
      @commands.capture(RbConfig.ruby, fixture("worker.rb"), "stdout_failure")
    end

    assert_includes error.message, "exit status 7"
    assert_includes error.message, "service is unavailable"
  end

  def test_prefers_stderr_over_captured_output_when_both_are_present
    error = assert_raises(RailsDev::Error) do
      @commands.capture(RbConfig.ruby, fixture("worker.rb"), "mixed_failure")
    end

    assert_includes error.message, "authentication failed"
    refute_includes error.message, "captured value"
  end

  def test_stops_descendants_as_well_as_the_launcher
    child = @commands.start("tree", [RbConfig.ruby, fixture("worker.rb"), "tree"], stream: false)
    deadline = @commands.monotonic_time + 5
    sleep 0.01 while child.running? && child.stdout.empty? && @commands.monotonic_time < deadline
    descendant = Integer(child.stdout.strip)
    @commands.stop

    assert_raises(Errno::ESRCH) { Process.kill(0, descendant) }
  end

  def test_shutdown_reaps_an_already_exited_child
    child = @commands.start("exited", [RbConfig.ruby, fixture("worker.rb"), "failure"], stream: false)
    deadline = @commands.monotonic_time + 5
    sleep 0.01 while RailsDev::ProcessTable.new.identity(child.pid) && @commands.monotonic_time < deadline

    refute RailsDev::ProcessTable.new.identity(child.pid)
    @commands.stop

    assert_equal 7, child.status.exitstatus
  end

  def test_lost_terminal_output_does_not_interrupt_forced_shutdown
    terminal = Object.new
    def terminal.write(*) = raise(Errno::EIO)
    @commands = RailsDev::Commands.new(@root, output: terminal, shutdown_timeout: 0.1)
    child = @commands.start("stubborn", [RbConfig.ruby, fixture("worker.rb"), "stubborn"])
    deadline = @commands.monotonic_time + 5
    sleep 0.01 while child.running? && child.stdout.empty? && @commands.monotonic_time < deadline
    @commands.stop

    assert_equal Signal.list.fetch("KILL"), child.status.termsig
  ensure
    Process.kill("KILL", child.pid) if child && !child.status
  end
end
