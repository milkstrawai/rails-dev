# frozen_string_literal: true

require "delegate"

module RailsDev
  class Output < SimpleDelegator
    def write(*)
      super
    rescue Errno::EIO, Errno::EPIPE
      0
    end

    def puts(*)
      super
    rescue Errno::EIO, Errno::EPIPE
      nil
    end

    def print(*)
      super
    rescue Errno::EIO, Errno::EPIPE
      nil
    end

    def flush
      super
    rescue Errno::EIO, Errno::EPIPE
      nil
    end
  end
end
