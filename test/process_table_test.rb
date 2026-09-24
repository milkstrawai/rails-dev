# frozen_string_literal: true

require "test_helper"

class ProcessTableTest < Minitest::Test
  def test_reports_missing_process_inspection_instead_of_claiming_cleanup_succeeded
    path = ENV.fetch("PATH")
    ENV["PATH"] = "/nonexistent"

    assert_raises(RailsDev::Error) { RailsDev::ProcessTable.new }
  ensure
    ENV["PATH"] = path
  end

  def test_identity_includes_the_process_group_and_start_time
    table = RailsDev::ProcessTable.new
    identity = table.identity(Process.pid)

    assert_equal [Process.pid, Process.getpgrp], identity.take(2)
    assert_kind_of String, identity.last
    assert_includes table, identity
    refute_includes table, [Process.pid, Process.getpgrp, "different start time"]
  end
end
