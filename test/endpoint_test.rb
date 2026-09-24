# frozen_string_literal: true

require "test_helper"

class EndpointTest < Minitest::Test
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
end
