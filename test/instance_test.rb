# frozen_string_literal: true

require "test_helper"

class InstanceTest < Minitest::Test
  include TestWorkspace

  def setup
    super
    @commands = RailsDev::Commands.new(@root, output: StringIO.new, shutdown_timeout: 0.1)
    @runtime = File.join(@workspace, "run-example")
    FileUtils.mkdir_p(@runtime)
    FileUtils.touch(File.join(@runtime, "owner.lock"))
    @instance = RailsDev::Instance.new(@runtime)
    @instance.record(**JSON.parse(File.read(fixture("run.json"))), shutdown_timeout: 0.1)
  end

  def teardown
    @commands.stop
    super
  end

  def test_escalates_when_a_descendant_ignores_termination_and_its_parent_exits
    child = @commands.start("tree", [RbConfig.ruby, fixture("worker.rb"), "stubborn-tree"], stream: false)
    deadline = @commands.monotonic_time + 5
    sleep 0.01 while child.running? && child.stdout.empty? && @commands.monotonic_time < deadline
    descendant = Integer(child.stdout.strip)
    @instance.record_processes([child.pid])
    @instance.stop

    refute RailsDev::ProcessTable.new.identity(descendant)
    refute_path_exists @runtime
  end

  def test_refuses_recovery_of_older_instances_without_ownership_information
    path = File.join(@runtime, "instance.json")
    File.write(path, JSON.generate(JSON.parse(File.read(path)).except("processes")))

    assert_equal "interrupted", @instance.snapshot.fetch("status")
    error = assert_raises(RailsDev::Error) { @instance.stop }

    assert_includes error.message, "Inspect #{path}"
    assert_includes error.message, "verify process ownership before manual cleanup"
    assert_path_exists @runtime
  end
end
