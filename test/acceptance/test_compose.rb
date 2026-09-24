# frozen_string_literal: true

require "test_helper"
require "securerandom"
require_relative "../support/cli_process"

class ComposeAcceptanceTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    @project = "rails-dev-test-#{SecureRandom.hex(6)}"
    @occupied = TCPServer.new("127.0.0.1", 0)
    @commands = RailsDev::Commands.new(@root, output: StringIO.new)
    @commands.env.merge!("RAILS_DEV_TEST_PROJECT" => @project, "COMPOSE_PROJECT_NAME" => @project,
                         "RAILS_DEV_TEST_OCCUPIED_PORT" => @occupied.addr[1].to_s)
    FileUtils.cp(fixture("postgres-compose.yml"), File.join(@root, "dev-docker-compose.yml"))
    @config = RailsDev::Configuration.load(@root, global_path: "/nonexistent")
    @config.compose_file = File.join(@root, "dev-docker-compose.yml")
    @config.connect("postgres", port: 5432, env: { "PGHOST" => "%{host}", "PGPORT" => "%{port}" })
    state = RailsDev::State.new(@commands, base: @workspace)
    @compose = RailsDev::Compose.new(@config, @commands, state, @workspace)
  end

  def teardown
    @commands.run("docker", "compose", "-p", @project, "-f", @config.compose_file, "down", "--volumes") if @config
    @commands&.stop
    @occupied&.close
    super
  end

  def test_docker_assigns_a_reachable_port_when_the_original_port_is_occupied
    endpoint = @compose.start
    response = docker("exec", "-T", "postgres", "psql", "-U", "fixture", "-Atc", "SELECT 1")

    refute_equal @occupied.addr[1].to_s, endpoint.fetch("PGPORT")
    assert_equal "1", response.strip
    TCPSocket.open(endpoint.fetch("PGHOST"), endpoint.fetch("PGPORT")) { |socket| refute_predicate socket, :closed? }
  end

  def test_reuses_the_same_container_and_keeps_it_after_command_cleanup
    first_endpoint = @compose.start
    first_id = docker("ps", "--quiet", "postgres").strip
    second_endpoint = @compose.start
    @commands.stop

    assert_equal first_endpoint, second_endpoint
    assert_equal first_id, docker("ps", "--quiet", "postgres").strip
  end

  def test_recovering_an_app_instance_preserves_its_shared_database
    @compose.start
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("service_config.rb"), File.join(@root, "config/rails_dev.rb"))
    FileUtils.cp(fixture("erb/Procfile.dev"), File.join(@root, "Procfile.dev"))
    env = @commands.env.slice("RAILS_DEV_TEST_PROJECT", "COMPOSE_PROJECT_NAME", "RAILS_DEV_TEST_OCCUPIED_PORT")
    env["PATH"] = ENV.fetch("PATH")
    pid = start_cli(env)
    runtime = ready_response(pid).fetch("runtime")
    container = docker("ps", "--quiet", "postgres").strip
    kill_launcher(pid, runtime)
    stopper = start_cli(arguments: ["stop", File.basename(runtime)])

    assert_equal 0, finish(stopper, nil).exitstatus, output(stopper)
    assert_equal container, docker("ps", "--quiet", "postgres").strip
    assert_equal "1", docker("exec", "-T", "postgres", "psql", "-U", "fixture", "-Atc", "SELECT 1").strip
  end

  def test_stop_and_start_keep_the_container_and_database_data
    @compose.start
    first_id = docker("ps", "--quiet", "postgres").strip
    docker("exec", "-T", "postgres", "psql", "-U", "fixture", "-c",
           "CREATE TABLE proof (value integer); INSERT INTO proof VALUES (42)")
    @compose.stop
    @compose.start

    assert_equal first_id, docker("ps", "--quiet", "postgres").strip
    assert_equal "42", docker("exec", "-T", "postgres", "psql", "-U", "fixture", "-Atc",
                              "SELECT value FROM proof").strip
  end

  private

  def docker(*)
    @commands.capture("docker", "compose", "-p", @project, "-f", @config.compose_file, *)
  end
end
