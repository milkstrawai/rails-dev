# frozen_string_literal: true

require "socket"

module RailsDev
  module Ports
    def self.available(first, excluding: [])
      (first..65_535).each do |port|
        next if excluding.include?(port)

        begin
          TCPServer.open("127.0.0.1", port) { return port }
        rescue Errno::EADDRINUSE, Errno::EACCES
          next
        end
      end
      raise Error, "No available local port at or above #{first}."
    end
  end
end
