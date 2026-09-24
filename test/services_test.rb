# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class ServicesTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(File.join(__dir__, "fixtures/service_config.rb"), File.join(@root, "config/rails_dev.rb"))
  end

  def test_start_launches_services_without_web_processes_or_preparation
    pid = start_cli(arguments: ["services", "start", "--root", @root])

    assert_equal 0, finish(pid, nil).exitstatus
    assert_equal(["compose_up"], events.map { |event| event.fetch("event") })
  end

  def test_stop_preserves_containers_and_volumes
    pid = start_cli(arguments: ["services", "stop", "--root", @root])

    assert_equal 0, finish(pid, nil).exitstatus
    assert_equal [{ "event" => "compose_stop", "arguments" => ["postgres"] }], events
  end

  def test_stop_does_not_require_valid_connection_mappings
    FileUtils.cp(fixture("stale_service_config.rb"), File.join(@root, "config/rails_dev.rb"))
    pid = start_cli(arguments: ["services", "stop", "--root", @root])

    assert_equal 0, finish(pid, nil).exitstatus
    assert_equal [{ "event" => "compose_stop", "arguments" => ["postgres"] }], events
  end

  def test_stop_does_nothing_when_every_service_is_excluded
    FileUtils.cp(fixture("excluded_service_config.rb"), File.join(@root, "config/rails_dev.rb"))
    pid = start_cli(arguments: ["services", "stop", "--root", @root])

    assert_equal 0, finish(pid, nil).exitstatus
    assert_empty events
  end

  def test_exec_preserves_test_environment_and_argument_boundaries
    path = File.join(@workspace, "result.json")
    arguments = ["--help", "-h", "--version", "-v", "--root", "child", "--skip-prepare",
                 "", "two words; $(false)", "--", "--root"]
    pid = start_cli({ "TEST_RESULT" => path, "RAILS_ENV" => "test" }, arguments: [
                      "services", "exec", "--root", @root, "--", RbConfig.ruby,
                      fixture("service_command.rb"), *arguments
                    ])

    assert_equal 0, finish(pid, nil).exitstatus
    result = JSON.parse(File.read(path))

    assert_equal "test", result.fetch("rails_env")
    assert_equal "45432", result.fetch("pgport")
    assert_equal arguments, result.fetch("argv")
    assert_nil result.fetch("pidfile")
  end

  def test_exec_returns_the_command_exit_status
    pid = start_cli({ "TEST_RESULT" => File.join(@workspace, "result.json"), "TEST_EXIT" => "7" }, arguments: [
                      "services", "exec", "--root", @root, "--", RbConfig.ruby, fixture("service_command.rb")
                    ])

    assert_equal 7, finish(pid, nil).exitstatus
  end

  def test_exec_does_not_force_development_environment
    path = File.join(@workspace, "result.json")
    pid = start_cli({ "TEST_RESULT" => path, "RAILS_ENV" => nil }, arguments: [
                      "services", "exec", "--root", @root, "--", RbConfig.ruby, fixture("service_command.rb")
                    ])
    finish(pid, nil)

    assert_nil JSON.parse(File.read(path)).fetch("rails_env")
  end

  def test_exec_preserves_standard_input
    path = File.join(@workspace, "result.json")
    reader, writer = IO.pipe
    writer.write("console input")
    writer.close
    pid = start_cli({ "TEST_RESULT" => path, "TEST_READ_STDIN" => "1" }, input: reader, arguments: [
                      "services", "exec", "--root", @root, "--", RbConfig.ruby, fixture("service_command.rb")
                    ])
    finish(pid, nil)

    assert_equal "console input", JSON.parse(File.read(path)).fetch("stdin")
  ensure
    reader&.close
    writer&.close unless writer&.closed?
  end
end
