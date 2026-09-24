# frozen_string_literal: true

require "test_helper"
require "timeout"

class StateTest < Minitest::Test
  include TestWorkspace

  def setup
    super
    @state = RailsDev::State.new(RailsDev::Commands.new(@root, output: StringIO.new), base: @workspace)
    @details = JSON.parse(File.read(fixture("run.json")))
  end

  def test_lists_owned_runs_and_removes_them_after_shutdown
    @state.with_run do |runtime|
      RailsDev::Instance.new(runtime).record(**@details)

      assert_equal [@details.merge("id" => File.basename(runtime))], @state.runs
    end

    assert_empty @state.runs
  end

  def test_a_service_command_without_app_metadata_is_not_an_instance
    @state.with_run do
      assert_empty @state.runs
    end
  end

  def test_lists_and_removes_stale_records_after_the_owner_is_killed
    command = [RbConfig.ruby, "-I", File.expand_path("../lib", __dir__),
               fixture("run_owner.rb"), fixture("run.json")]
    runtime = nil
    IO.popen({ "XDG_STATE_HOME" => @workspace }, command) do |owner|
      runtime = Timeout.timeout(5) { owner.gets }.strip
    ensure
      Process.kill("KILL", owner.pid)
    end

    assert_path_exists runtime
    assert_equal "stale", @state.runs.fetch(0).fetch("status")
    @state.stop(File.basename(runtime))

    assert_empty @state.runs
    refute_path_exists runtime
  end

  def test_an_empty_list_does_not_create_state_directories
    assert_empty @state.runs
    refute_path_exists @state.directory
  end

  def test_releases_the_lock_after_failure
    assert_raises(RailsDev::Error) do
      @state.synchronize(@root) { raise RailsDev::Error, "Preparation failed" }
    end

    File.open(Dir.glob(File.join(@state.directory, "*.lock")).fetch(0), File::RDWR) do |file|
      assert file.flock(File::LOCK_EX | File::LOCK_NB)
    end
  end
end
