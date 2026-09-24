# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class EnvironmentTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("service_config.rb"), File.join(@root, "config/rails_dev.rb"))
    FileUtils.cp(fixture("service_command.rb"), File.join(@root, "service_command.rb"))
    @result = File.join(@workspace, "result.json")
  end

  def test_service_commands_receive_mapped_connections_without_loading_tools
    pid = execute({ "PGPORT" => "12345" })

    assert_equal 0, finish(pid, nil).exitstatus
    assert_equal "45432", JSON.parse(File.read(@result)).fetch("pgport")
  end

  def test_app_command_can_supply_its_own_environment
    pid = execute({}, command: ["env", "PGPORT=12345", RbConfig.ruby, "service_command.rb"])

    assert_equal 0, finish(pid, nil).exitstatus
    assert_equal "12345", JSON.parse(File.read(@result)).fetch("pgport")
  end

  def test_exec_without_compose_uses_the_existing_connection
    File.unlink(File.join(@root, "config/rails_dev.rb"))
    pid = execute({ "PGPORT" => "23456" })

    assert_equal 0, finish(pid, nil).exitstatus
    assert_equal "23456", JSON.parse(File.read(@result)).fetch("pgport")
    assert_empty events
  end

  private

  def execute(env, command: [RbConfig.ruby, "service_command.rb"])
    start_cli({ "TEST_RESULT" => @result }.merge(env),
              arguments: ["services", "exec", "--root", @root, "--", *command])
  end
end
