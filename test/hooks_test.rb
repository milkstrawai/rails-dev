# frozen_string_literal: true

require "test_helper"

class HooksTest < Minitest::Test
  include TestWorkspace

  def setup
    super
    @config = RailsDev::Configuration.new
    @output = StringIO.new
    @context = RailsDev::Commands.new(@root, output: @output)
    @hooks = RailsDev::Hooks.new(@config, @context)
  end

  def test_runs_callbacks_in_registration_order
    events = []
    @config.before_start { events << :global }
    @config.before_start { events << :app }
    @hooks.call(:before_start)

    assert_equal %i[global app], events
  end

  def test_nests_around_hooks_in_registration_order
    events = []
    @config.around_run do |_run, continue|
      events << :global_enter
      continue.call
    ensure
      events << :global_exit
    end
    @config.around_run do |_run, continue|
      events << :app_enter
      continue.call
    ensure
      events << :app_exit
    end
    @hooks.around { events << :run }

    assert_equal %i[global_enter app_enter run app_exit global_exit], events
  end

  def test_reports_a_hook_failure_with_its_name
    @config.after_ready { raise "notification failed" }
    error = assert_raises(RailsDev::Error) { @hooks.call(:after_ready) }

    assert_equal "after_ready hook failed: notification failed", error.message
  end

  def test_around_teardown_preserves_rubys_exception_chain
    original = RailsDev::Error.new("Rails failed")
    @config.around_run do |_run, continue|
      continue.call
    ensure
      raise "around cleanup failed"
    end
    error = assert_raises(RailsDev::Error) { @hooks.around { raise original } }

    assert_equal "around_run hook failed: around cleanup failed", error.message
    assert_same original, error.cause.cause
  end

  def test_an_around_hook_can_handle_an_action_failure
    handled = false
    @config.around_run do |_run, continue|
      continue.call
    rescue RailsDev::Error
      handled = true
    end
    @hooks.around { raise RailsDev::Error, "Rails failed" }

    assert handled
  end

  def test_attempts_all_stop_hooks_in_reverse_order_when_one_fails
    events = []
    @config.after_stop { events << :global }
    @config.after_stop { raise "app cleanup failed" }
    @config.after_stop { events << :local }
    error = assert_raises(RailsDev::Error) { @hooks.after_stop }

    assert_equal %i[local global], events
    assert_includes error.message, "after_stop hook failed: app cleanup failed"
  end

  def test_keeps_the_original_interrupt_when_a_stop_hook_fails
    original = RailsDev::Interrupted.new("TERM")
    @config.after_stop { raise "cleanup failed" }
    error = assert_raises(RailsDev::Interrupted) { @hooks.after_stop(original) }

    assert_same original, error
    assert_includes @output.string, "after_stop hook failed: cleanup failed"
  end
end
