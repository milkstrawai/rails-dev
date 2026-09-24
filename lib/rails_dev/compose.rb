# frozen_string_literal: true

require "json"
require "rubygems/version"

module RailsDev
  class Compose
    attr_reader :lock_key

    def initialize(config, commands, state, runtime)
      @config = config
      @commands = commands
      @state = state
      @runtime = runtime
      @base = ["docker", "compose", "-f", config.compose_file]
      @base += config.profiles.flat_map { |profile| ["--profile", profile] }
    end

    def start
      check_version!
      load_project
      @plan = ServicePorts.new(@services, @config)
      return {} if @services.empty?

      prepare_ports
      @state.synchronize(lock_key) do
        @commands.run(*@command, "up", "-d", "--wait", "--wait-timeout", @config.startup_timeout.to_s,
                      "--no-recreate", *@services.keys)
        @plan.environment(endpoints)
      end
    end

    def stop
      load_project
      return if @services.empty?

      @state.synchronize(lock_key) do
        @commands.say("Stopping shared services: #{@services.keys.join(", ")}. Containers and volumes are kept.")
        @commands.run(*@base, "stop", *@services.keys)
      end
    end

    private

    def check_version!
      version = @commands.capture("docker", "compose", "version", "--short").strip.delete_prefix("v")
      return if Gem::Version.correct?(version) && Gem::Version.new(version) >= Gem::Version.new("2.24.4")

      raise Error, "Docker Compose 2.24.4 or newer is required for port overrides."
    end

    def load_project
      model = JSON.parse(@commands.capture(*@base, "config", "--format", "json"))
      @lock_key = "compose:#{model.fetch("name")}"
      @services = model.fetch("services", {}).except(*@config.exclude_services)
    end

    def prepare_ports
      path = File.join(@runtime, "compose.ports.yml")
      File.write(path, @plan.override, perm: 0o600)
      @command = [*@base, "-f", path]
      @commands.capture(*@command, "config", "--quiet")
    end

    def endpoints
      publications = published_ports
      @plan.ports.each_with_object({}) do |(service, ports), result|
        ports.each do |port|
          target, protocol = port.values_at("target", "protocol")
          result[[service, target, protocol]] = endpoint(service, target, protocol, publications.fetch(service, []))
        end
      end
    end

    def published_ports
      containers = @commands.capture(*@command, "ps", "--all", "--format", "json", *@services.keys)
                            .lines.map { |line| JSON.parse(line) }
      containers.group_by { |container| container.fetch("Service") }.transform_values do |group|
        group.flat_map { |container| container["Publishers"] || [] }
      end
    end

    def endpoint(service, target, protocol, publishers)
      bindings = publishers.select do |port|
        port["TargetPort"] == target && port["Protocol"] == protocol && port["PublishedPort"].positive?
      end
      unless bindings.one? && bindings.first["URL"] == "127.0.0.1"
        raise Error, "#{service}:#{target}/#{protocol} must publish one port on 127.0.0.1; " \
                     "Docker returned #{bindings.inspect}. Existing containers are not recreated automatically."
      end

      published = bindings.first.fetch("PublishedPort").to_s
      @commands.say("#{service}:#{target}/#{protocol} -> 127.0.0.1:#{published} (shared; kept running on exit)")
      { host: "127.0.0.1", port: published }
    end
  end
end
