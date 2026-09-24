# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class ListTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    @state = RailsDev::State.new(base: @workspace)
    @details = JSON.parse(File.read(fixture("run.json")))
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("https_config.rb"), File.join(@root, "config/rails_dev.rb"))
    FileUtils.cp(fixture("http_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    @rails_socket = TCPServer.new("127.0.0.1", 0)
    @vite_socket = TCPServer.new("127.0.0.1", 0)
  end

  def teardown
    super
  ensure
    @rails_socket&.close
    @vite_socket&.close
  end

  def test_lists_all_projects_without_loading_app_configuration
    @state.with_run do |first|
      RailsDev::Instance.new(first).record(**@details, "root" => @root)
      @state.with_run do |second|
        RailsDev::Instance.new(second).record(**@details, "name" => "other", "root" => "/apps/other", "pid" => 67_890)
        listing = list

        assert_includes listing, @root
        assert_includes listing, "/apps/other"
        assert_includes listing, "67890"
        assert_includes listing, File.basename(first)
      end
    end
  end

  def test_filters_by_checkout_with_root
    @state.with_run do |first|
      RailsDev::Instance.new(first).record(**@details, "root" => @root)
      @state.with_run do |second|
        RailsDev::Instance.new(second).record(**@details, "root" => "/apps/other", "pid" => 67_890)
        listing = list("--root", @root)

        assert_includes listing, @root
        refute_includes listing, "/apps/other"
      end
    end
  end

  def test_lists_both_runs_from_one_checkout_and_removes_only_the_stopped_run
    first = start_app
    first_response = ready_response(first)
    second = start_app
    second_response = ready_response(second)
    listing = list

    assert_includes listing, "http://127.0.0.1:#{first_response.fetch("rails_port")}"
    assert_includes listing, second_response.fetch("vite_url")
    finish(first)
    listing = list

    refute_match(/\b#{first}\b/, listing)
    assert_match(/\b#{second}\b/, listing)
    finish(second)
  end

  def test_lists_a_starting_run_before_readiness
    gate = File.join(@workspace, "ready.gate")
    File.write(gate, "")
    pid = start_app("TEST_READY_GATE" => gate)
    wait_until(pid) { events.any? { |event| event["event"] == "started" } }
    listing = list

    assert_includes listing, "starting"
    assert_match(/\b#{pid}\b/, listing)
    File.unlink(gate)
    ready_response(pid)

    assert_includes list, "ready"
    finish(pid)
  end

  def test_explains_an_empty_list_without_creating_state
    assert_equal "No instances.\n", list
    refute_path_exists @state.directory
  end

  private

  def start_app(env = {})
    start_cli({ "TEST_RAILS_PORT" => @rails_socket.addr[1].to_s,
                "TEST_VITE_PORT" => @vite_socket.addr[1].to_s }.merge(env))
  end

  def list(*arguments)
    pid = start_cli(arguments: ["list", *arguments])

    assert_equal 0, finish(pid, nil).exitstatus, output(pid)
    output(pid)
  end
end
