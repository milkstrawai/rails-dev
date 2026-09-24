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

  def test_timeout_stops_the_app_and_removes_its_runtime
    configure("readiness: { timeout: 0.4 }")
    pid = start_cli({ "TEST_HTTP_STATUS" => "503" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_match(%r{web \(GET http://127\.0\.0\.1:\d+/up\): HTTP 503; expected 200}, output(pid))
    started = events.find { |event| event["event"] == "started" }

    assert_raises(Errno::ESRCH) { Process.kill(0, started.fetch("pid")) }
    refute_path_exists started.fetch("runtime")
  end

  def test_readiness_diagnostics_omit_query_values_headers_and_bodies
    configure('readiness: { timeout: 0.4, path: "/health?token=private-query", method: "POST", ' \
              'headers: { "Authorization" => "private-header" }, body: "private-body" }')
    pid = start_cli({ "TEST_HTTP_STATUS" => "503" })

    assert_equal 1, finish(pid, nil).exitstatus
    assert_match(%r{web \(POST http://127\.0\.0\.1:\d+/health\): HTTP 503}, output(pid))
    refute_match(/private-(query|header|body)/, output(pid))
    assert_includes output(pid), "Check the process output and readiness settings."
  end

  def test_explains_a_failing_custom_success_condition
    configure("readiness: { timeout: 0.4, success: ->(_response) { false } }")
    pid = start_cli

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "HTTP 200; expected a passing custom success check"
    refute_includes output(pid), "#<Proc"
  end

  def test_explains_a_failing_custom_readiness_check
    File.write(File.join(@root, "config/rails_dev.local.rb"), <<~RUBY)
      RailsDev.configure do |config|
        config.readiness = { timeout: 0.4 }
        config.http :web, readiness: ->(_endpoint) { false }
      end
    RUBY
    pid = start_cli

    assert_equal 1, finish(pid, nil).exitstatus
    assert_includes output(pid), "web (custom readiness check): check did not pass"
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
