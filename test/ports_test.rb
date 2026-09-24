# frozen_string_literal: true

require "test_helper"

class PortsTest < Minitest::Test
  def test_skips_an_occupied_port
    TCPServer.open("127.0.0.1", 0) do |occupied|
      port = occupied.addr[1]

      assert_operator RailsDev::Ports.available(port), :>, port
    end
  end

  def test_reuses_a_released_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close

    assert_equal port, RailsDev::Ports.available(port)
    TCPServer.open("127.0.0.1", port) { |listener| assert_equal port, listener.addr[1] }
  end

  def test_excludes_a_port_selected_for_another_child
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close

    assert_operator RailsDev::Ports.available(port, excluding: [port]), :>, port
  end
end
