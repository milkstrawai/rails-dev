# frozen_string_literal: true

require "test_helper"
require "net/http"
require_relative "../support/cli_process"

class HTTPSAcceptanceTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("https_config.rb"), File.join(@root, "config/rails_dev.rb"))
    @directory = File.join(@workspace, "proxy")
    @output_path = File.join(@workspace, "proxy.log")
    @proxy_output = File.open(@output_path, "w")
    @proxy_commands = RailsDev::Commands.new(@root, output: @proxy_output)
    @proxy_commands.env.merge!("PORTLESS_STATE_DIR" => @directory, "PORTLESS_SYNC_HOSTS" => "0")
    @portless = RailsDev::Portless.new(@proxy_commands)
    @portless.install
    @proxy_port = TCPServer.open("127.0.0.1", 0) { |socket| socket.addr[1] }
    @rails_socket = TCPServer.new("127.0.0.1", 0)
    @vite_socket = TCPServer.new("127.0.0.1", 0)
    data = ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local/share"))
    @library = File.join(data, "rails-dev/portless", RailsDev::Portless::VERSION,
                         "lib/node_modules/portless/dist/index.js")
    cli = File.join(File.dirname(@library), "cli.js")
    @proxy = @proxy_commands.start("proxy", ["node", cli, "proxy", "start", "--foreground", "--skip-trust",
                                             "--port", @proxy_port.to_s, "--https", "--tld", "localhost"])
    wait_until do
      @proxy.poll
      File.file?(File.join(@directory, "proxy.pid"))
    end
    @portless.check
  end

  def teardown
    @proxy_commands&.stop
  ensure
    begin
      super
    ensure
      @proxy_output&.close
      @rails_socket&.close
      @vite_socket&.close
    end
  end

  def test_two_runs_have_verified_https_origins_and_their_own_asset_urls
    first = start_https
    second = start_https
    first_url, first_body = ready_response(first)
    second_url, second_body = ready_response(second)

    refute_equal first_url, second_url
    assert_equal "https", first_body.fetch("scheme")
    assert_equal URI(first_url).host, first_body.fetch("host").split(":").first
    refute_equal first_body.fetch("vite_url"), second_body.fetch("vite_url")
    assert_equal "vite", JSON.parse(request(second_body.fetch("vite_url")).body).fetch("role")
    finish(first)
    finish(second)
  end

  def test_stopping_one_run_removes_only_its_routes
    first = start_https
    first_url, first_body = ready_response(first)
    second = start_https
    second_url, = ready_response(second)
    finish(first)
    wait_until(second) { request(first_url).code == "404" }

    assert_equal "404", request(first_body.fetch("vite_url")).code
    assert_equal "200", request(second_url).code
    assert_predicate @proxy, :running?
    finish(second)
  end

  def test_recovery_removes_only_the_orphaned_instances_routes
    first = start_https
    first_url, first_body = ready_response(first)
    second = start_https
    second_url, = ready_response(second)
    kill_launcher(first, first_body.fetch("runtime"))
    stopper = start_cli(arguments: ["stop", File.basename(first_body.fetch("runtime"))])

    assert_equal 0, finish(stopper, nil).exitstatus, output(stopper)
    assert_equal "404", request(first_url).code
    assert_equal "404", request(first_body.fetch("vite_url")).code
    assert_equal "200", request(second_url).code
    assert_predicate @proxy, :running?
    finish(second)
  end

  def test_interrupting_the_route_owner_cleans_up_the_run
    pid = start_https
    _, body = ready_response(pid)
    Process.kill("INT", routes.first.fetch("pid"))

    assert_equal 1, finish(pid, nil).exitstatus
    assert_empty routes
    refute_path_exists body.fetch("runtime")
  end

  def test_rails_failure_cleans_up_its_routes_and_vite
    first = start_https
    first_url, = ready_response(first)
    second = start_https({ "TEST_FAIL_RAILS" => "1" })

    assert_equal 1, finish(second, nil).exitstatus
    started = events.select { |event| event["event"] == "started" && event["role"] == "vite" }
    failed = started.last

    assert_raises(Errno::ESRCH) { Process.kill(0, failed.fetch("pid")) }
    refute_path_exists failed.fetch("runtime")
    assert_equal 2, routes.size
    assert_equal "200", request(first_url).code
    finish(first)
  end

  def test_retrying_a_bind_failure_replaces_its_routes
    pid = start_https({ "TEST_BIND_CONFLICT" => "1" })
    url, = ready_response(pid)

    assert_includes output(pid), "selecting ports again"
    assert_equal 2, routes.size
    assert_equal "200", request(url).code
    finish(pid)

    assert_empty routes
  end

  def test_ready_hook_failure_cleans_up_only_its_own_routes
    first = start_https
    first_url, = ready_response(first)
    FileUtils.cp(fixture("failing_ready_hook.rb"), File.join(@root, "config/rails_dev.local.rb"))
    second = start_https

    assert_equal 1, finish(second, nil).exitstatus
    assert_includes output(second), "after_ready hook failed: Ready hook failed"
    assert_equal 2, routes.size
    assert_equal "200", request(first_url).code
    finish(first)
  end

  def test_extra_process_failure_cleans_up_only_its_own_routes
    first = start_https
    first_url, = ready_response(first)
    FileUtils.cp(fixture("integrations_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    second = start_https({ "TEST_PROCESS_COMMAND" => fixture("process.rb") }, with: ["worker"])
    _, body = ready_response(second)
    worker = events.find { |event| event["event"] == "process_started" }
    Process.kill("TERM", worker.fetch("pid"))

    assert_equal 0, finish(second, nil).exitstatus
    refute_path_exists body.fetch("runtime")
    assert_equal 2, routes.size
    assert_equal "200", request(first_url).code
    finish(first)
  end

  def test_an_existing_route_is_not_removed_when_registration_fails_partway
    rails_port = RailsDev::Ports.available(@rails_socket.addr[1])
    route = { "example-#{rails_port}-js.localhost" => @vite_socket.addr[1] }
    helper = File.expand_path("../../lib/rails_dev/portless.mjs", __dir__)
    owner = @proxy_commands.start("owner", ["node", helper, @library, @directory, JSON.generate(route)],
                                  ready_message: "HTTPS routes registered")
    wait_until do
      owner.poll
      owner.ready?
    end
    existing = routes
    pid = start_https

    assert_equal 1, finish(pid, nil).exitstatus
    assert_equal existing, routes
    assert_predicate owner, :running?
  end

  def test_missing_proxy_fails_before_starting_compose
    @proxy_commands.stop
    pid = start_https

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "rails-dev setup"
    assert_empty events
  end

  private

  def start_https(env = {}, with: [])
    start_cli({ "PORTLESS_STATE_DIR" => @directory, "TEST_RAILS_PORT" => @rails_socket.addr[1].to_s,
                "TEST_VITE_PORT" => @vite_socket.addr[1].to_s }.merge(env),
              arguments: ["start", "--root", @root, *(with.empty? ? [] : ["--with", *with])])
  end

  def ready_response(pid)
    wait_until(pid) { output(pid).include?("Ready:") }
    url = output(pid).match(%r{Ready: (https://\S+)})[1]
    response = wait_until(pid) do
      result = request(url)
      result if result.code == "200"
    end
    [url, JSON.parse(response.body)]
  end

  def request(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.ipaddr = "127.0.0.1"
    http.use_ssl = true
    http.ca_file = File.join(@directory, "ca.pem")
    http.open_timeout = http.read_timeout = 3
    http.get("/")
  end

  def routes
    JSON.parse(File.read(File.join(@directory, "routes.json")))
  end
end
