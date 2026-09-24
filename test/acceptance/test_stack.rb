# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "net/http"

class StackAcceptanceTest < Minitest::Test
  include TestWorkspace

  def setup
    super
    @project = "rails-dev-stack-#{SecureRandom.hex(5)}"
    @occupied = TCPServer.new("127.0.0.1", 0)
    @commands = RailsDev::Commands.new(@root, output: StringIO.new)
    @commands.env.merge!("RAILS_DEV_TEST_PROJECT" => @project, "COMPOSE_PROJECT_NAME" => @project,
                         "RAILS_DEV_TEST_OCCUPIED_PORT" => @occupied.addr[1].to_s)
    FileUtils.cp(fixture("stack-compose.yml"), File.join(@root, "dev-docker-compose.yml"))
    @config = RailsDev::Configuration.load(@root, global_path: "/nonexistent")
    @config.compose_file = File.join(@root, "dev-docker-compose.yml")
    @config.exclude_services = ["excluded"]
    @config.connect("redis", port: 6379, env: { "REDIS_PORT" => "%{port}" })
    @config.connect("clickhouse", port: 8123, env: { "CLICKHOUSE_URL" => "http://%{host}:%{port}" })
    @config.connect("clickhouse", port: 9000, env: { "CLICKHOUSE_NATIVE_PORT" => "%{port}" })
    @state = RailsDev::State.new(@commands, base: @workspace)
  end

  def teardown
    if @config
      @commands.run("docker", "compose", "-p", @project, "-f", @config.compose_file,
                    "--profile", "*", "down", "--volumes")
    end
    @commands&.stop
    @occupied&.close
    super
  end

  def test_redis_and_both_clickhouse_ports_are_reachable
    env = compose.start
    redis = TCPSocket.open("127.0.0.1", env.fetch("REDIS_PORT")) do |socket|
      socket.write("PING\r\n")
      socket.gets
    end
    request = Net::HTTP::Get.new("/?query=SELECT%201")
    request.basic_auth("fixture", "fixture")
    url = URI(env.fetch("CLICKHOUSE_URL"))
    response = Net::HTTP.start(url.host, url.port) { |http| http.request(request) }

    assert_equal "+PONG\r\n", redis
    assert_equal "1\n", response.body
    TCPSocket.open("127.0.0.1", env.fetch("CLICKHOUSE_NATIVE_PORT")) { |socket| refute_predicate socket, :closed? }
  end

  def test_dependencies_finish_and_internal_and_disabled_services_stay_unpublished
    compose.start
    containers = @commands.capture("docker", "compose", "-f", @config.compose_file,
                                   "ps", "--all", "--format", "json").lines.map { |line| JSON.parse(line) }
    setup = containers.find { |container| container["Service"] == "setup" }
    internal = containers.find { |container| container["Service"] == "internal" }

    assert_equal 0, setup.fetch("ExitCode")
    refute((internal.fetch("Publishers") || []).any? { |port| port["PublishedPort"].positive? })
    refute(containers.any? { |container| %w[excluded optional].include?(container["Service"]) })
  end

  def test_profile_activation_and_explicit_publication
    @config.profiles = ["debug"]
    @config.publish_ports["internal"] = [6379]
    @config.connect("internal", port: 6379, env: { "INTERNAL_PORT" => "%{port}" })
    @config.connect("optional", port: 6379, env: { "OPTIONAL_PORT" => "%{port}" })
    env = compose.start

    assert_match(/\A\d+\z/, env.fetch("INTERNAL_PORT"))
    assert_match(/\A\d+\z/, env.fetch("OPTIONAL_PORT"))
    refute_equal env.fetch("INTERNAL_PORT"), env.fetch("OPTIONAL_PORT")
  end

  def test_excluding_a_required_dependency_fails_before_startup
    @config.exclude_services << "setup"

    error = assert_raises(RailsDev::Error) { compose.start }

    assert_includes error.message, "setup"
    assert_empty @commands.capture("docker", "compose", "-f", @config.compose_file, "ps", "--all", "--quiet").strip
  end

  private

  def compose
    RailsDev::Compose.new(@config, @commands, @state, @workspace)
  end
end
