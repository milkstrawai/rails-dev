# frozen_string_literal: true

require "test_helper"
require "securerandom"

class BindingsAcceptanceTest < Minitest::Test
  include TestWorkspace

  def setup
    super
    @project = "rails-dev-bindings-#{SecureRandom.hex(5)}"
    @commands = RailsDev::Commands.new(@root, output: StringIO.new)
    @commands.env.merge!("RAILS_DEV_TEST_PROJECT" => @project, "COMPOSE_PROJECT_NAME" => @project)
    FileUtils.cp(fixture("multiple-bindings-compose.yml"), File.join(@root, "dev-docker-compose.yml"))
    @config = RailsDev::Configuration.load(@root, global_path: "/nonexistent")
    @config.compose_file = File.join(@root, "dev-docker-compose.yml")
    @state = RailsDev::State.new(@commands, base: @workspace)
  end

  def teardown
    @commands.run("docker", "compose", "-p", @project, "-f", @config.compose_file, "down", "--volumes") if @config
    @commands&.stop
    super
  end

  def test_rejects_an_additional_binding_on_a_reused_container
    @commands.run("docker", "compose", "-f", @config.compose_file, "up", "-d", "--wait")
    compose = RailsDev::Compose.new(@config, @commands, @state, @workspace)

    error = assert_raises(RailsDev::Error) { compose.start }

    assert_includes error.message, "must publish one port on 127.0.0.1"
    assert_includes error.message, "127.0.0.2"
  end
end
