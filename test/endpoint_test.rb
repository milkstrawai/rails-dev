# frozen_string_literal: true

require "test_helper"

class EndpointTest < Minitest::Test
  def test_timeout_reports_the_last_http_failure
    error = timeout_error(status: 503)

    assert_match(%r{web \(GET http://127\.0\.0\.1:\d+/up\): HTTP 503; expected 200}, error.message)
    assert_includes error.message, "Check the process output and readiness settings."
  end

  def test_readiness_diagnostics_omit_query_values_headers_and_bodies
    error = timeout_error(status: 503, readiness: {
                            path: "/health?token=private-query", method: "POST",
                            headers: { "Authorization" => "private-header" }, body: "private-body"
                          })

    assert_match(%r{web \(POST http://127\.0\.0\.1:\d+/health\): HTTP 503}, error.message)
    refute_match(/private-(query|header|body)/, error.message)
  end

  def test_explains_a_failing_custom_success_condition
    error = timeout_error(status: 200, readiness: { success: ->(_response) { false } })

    assert_includes error.message, "HTTP 200; expected a passing custom success check"
    refute_includes error.message, "#<Proc"
  end

  def test_timeout_reports_the_last_connection_failure
    port = TCPServer.open("127.0.0.1", 0) { |socket| socket.addr[1] }
    endpoint = RailsDev::Endpoint.new("web", port: port, env: "PORT", readiness: "/up")
    endpoint.allocate
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    refute endpoint.ready?(now + 5)
    error = assert_raises(RailsDev::Error) { endpoint.ready?(now - 1) }

    assert_includes error.message, "GET http://127.0.0.1:#{endpoint.port}/up"
    assert_includes error.message, "ECONNREFUSED"
  end

  private

  def timeout_error(status:, readiness: {})
    TCPServer.open("127.0.0.1", 0) do |server|
      endpoint = RailsDev::Endpoint.new("web", port: server.addr[1], env: "PORT",
                                               readiness: { path: "/up" }.merge(readiness))
      endpoint.url = "http://127.0.0.1:#{endpoint.port}"
      responder = Thread.new { respond(server, status) }

      refute endpoint.ready?(Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5)
      assert_raises(RailsDev::Error) { endpoint.ready?(0) }
    ensure
      responder&.kill&.join
    end
  end

  def respond(server, status)
    client = server.accept
    length = 0
    while (line = client.gets) && line != "\r\n"
      length = line.split(":", 2).last.to_i if line.downcase.start_with?("content-length:")
    end
    client.read(length)
    client.write("HTTP/1.1 #{status} Response\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
  ensure
    client&.close
  end
end
