# frozen_string_literal: true

module RailsDev
  class Foreman
    attr_reader :endpoints

    def initialize(root, config)
      @root = root
      @config = config
      @path = File.expand_path(config.procfile, root)
      @names = File.readlines(@path).filter_map { |line| line[/\A([A-Za-z0-9_-]+):\s*.+/, 1] }.uniq
      @endpoints = config.endpoints
      validate!
      @endpoints.select! { |endpoint| selected?(endpoint.name) }
    end

    def command
      [RbConfig.ruby, Gem.bin_path("foreman", "foreman"), "start", "--procfile", @path, "--root", @root,
       "--port", base_port.to_s, "--formation", formation,
       "--timeout", @config.shutdown_timeout.to_s]
    end

    private

    def validate!
      missing = (endpoints.map(&:name) + @config.optional_processes.keys).uniq - @names
      raise Error, "#{@config.procfile} is missing processes: #{missing.join(", ")}." unless missing.empty?
      raise Error, "The primary web process must be enabled." unless selected?(@config.web.to_s)
    end

    def selected?(name)
      selection = @config.optional_processes[name]
      !selection || @config.enabled?(selection)
    end

    def base_port
      port = endpoints.find { |endpoint| endpoint.name == @config.web.to_s }.port
      port - (@names.index(@config.web.to_s) * 100)
    end

    def formation
      @names.map { |name| "#{name}=#{selected?(name) ? 1 : 0}" }.join(",")
    end
  end
end
