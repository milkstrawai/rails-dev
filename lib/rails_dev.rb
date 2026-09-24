# frozen_string_literal: true

require_relative "rails_dev/version"

module RailsDev
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: 1)
      @status = status
      super(message)
    end
  end

  class Interrupted < Error
    attr_reader :signal

    def initialize(signal)
      @signal = signal
      super("Stopped.")
    end
  end

  def self.configure
    raise Error, "Configuration must be loaded by rails-dev." unless @configuration

    yield @configuration
  end

  def self.load_configuration(configuration, paths)
    @configuration = configuration
    paths.each { |path| load path if File.file?(path) }
  ensure
    @configuration = nil
  end
end

require_relative "rails_dev/configuration"
require_relative "rails_dev/ports"
require_relative "rails_dev/endpoint"
require_relative "rails_dev/foreman"
require_relative "rails_dev/output"
require_relative "rails_dev/process_table"
require_relative "rails_dev/instance"
require_relative "rails_dev/child"
require_relative "rails_dev/commands"
require_relative "rails_dev/state"
require_relative "rails_dev/service_ports"
require_relative "rails_dev/compose"
require_relative "rails_dev/services"
require_relative "rails_dev/portless"
require_relative "rails_dev/tailscale"
require_relative "rails_dev/hooks"
require_relative "rails_dev/session"
require_relative "rails_dev/cli"
