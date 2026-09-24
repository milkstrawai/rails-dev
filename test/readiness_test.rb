# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class ReadinessTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    File.write(File.join(@root, "Procfile.dev"), "web: bin/rails server\n")
    @socket = TCPServer.new("127.0.0.1", 0)
    @gate = File.join(@workspace, "ready.gate")
    File.write(File.join(@root, "config/rails_dev.rb"), <<~RUBY)
      RailsDev.configure do |config|
        config.https = false
        config.http :web, port: #{@socket.addr[1]}
        config.after_ready { |run| run.say("After readiness") }
      end
    RUBY
  end

  def teardown
    super
  ensure
    @socket.close
  end

  def test_listening_and_startup_logs_do_not_establish_readiness
    File.write(@gate, "")
    pid = start_cli({ "TEST_READY_GATE" => @gate, "TEST_RECORD_REQUESTS" => "1" })
    wait_until(pid) { events.any? { |event| event["event"] == "request" } }

    refute_includes output(pid), "After readiness"
    File.unlink(@gate)
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_includes output(pid), "After readiness"
    finish(pid)
  end

  def test_http_request_and_success_condition_are_app_owned
    configure('readiness: { path: "/health", method: "POST", ' \
              'headers: { "X-Probe" => "ready" }, body: "check", success: 202 }')
    pid = start_cli({ "TEST_HTTP_STATUS" => "202", "TEST_RECORD_REQUESTS" => "1" })
    wait_until(pid) { output(pid).include?("Ready:") }
    request = events.find { |event| event["event"] == "request" }

    assert_equal "POST", request.fetch("method")
    assert_equal "/health", request.fetch("path")
    assert_equal "ready", request.fetch("headers").fetch("x-probe")
    assert_equal "check", request.fetch("body")
    finish(pid)
  end

  def test_shared_settings_preserve_unspecified_defaults
    File.write(File.join(@root, "config/rails_dev.local.rb"),
               "RailsDev.configure { |config| config.readiness = { success: 202 } }\n")
    pid = start_cli({ "TEST_HTTP_STATUS" => "202" })
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_includes output(pid), "After readiness"
    finish(pid)
  end

  def test_timeout_stops_owned_processes_and_removes_the_runtime
    snapshot = File.join(@workspace, "timed-out-instance.json")
    File.write(File.join(@root, "config/rails_dev.local.rb"), <<~RUBY)
      RailsDev.configure do |config|
        session = nil
        config.before_start { |run| session = run }
        config.readiness = { timeout: 0.4 }
        config.http :web, readiness: lambda { |_endpoint|
          instance = JSON.parse(File.read(File.join(session.runtime, "instance.json")))
          File.write(#{snapshot.dump}, JSON.generate(instance.merge("runtime" => session.runtime)))
          false
        }
      end
    RUBY
    pid = start_cli

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "web (custom readiness check): check did not pass"
    instance = JSON.parse(File.read(snapshot))
    group = instance.fetch("processes").fetch(0).fetch(1)

    assert_empty RailsDev::ProcessTable.new.members([group])
    refute_path_exists instance.fetch("runtime")
  end

  def test_custom_check_can_wait_for_an_app_owned_file
    File.write(@gate, "")
    configure("readiness: ->(_endpoint) { !File.exist?(#{@gate.dump}) }")
    pid = start_cli
    wait_until(pid) { events.any? { |event| event["event"] == "started" } }

    refute_includes output(pid), "Ready:"
    File.unlink(@gate)
    wait_until(pid) { output(pid).include?("Ready:") }
    finish(pid)
  end

  def test_disabled_checks_accept_a_running_process_without_http_success
    configure("readiness: false")
    pid = start_cli({ "TEST_HTTP_STATUS" => "503" })
    wait_until(pid) { output(pid).include?("Ready:") }

    assert_includes output(pid), "After readiness"
    finish(pid)
  end

  private

  def configure(options)
    File.write(File.join(@root, "config/rails_dev.local.rb"),
               "RailsDev.configure { |config| config.http :web, #{options} }\n")
  end
end
