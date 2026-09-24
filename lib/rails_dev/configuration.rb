# frozen_string_literal: true

module RailsDev
  class Configuration
    HOOKS = %i[before_start after_ready after_stop around_run].freeze

    attr_accessor :compose_file, :procfile, :web, :startup_timeout, :shutdown_timeout, :readiness, :https, :name,
                  :env, :exclude_services, :profiles, :publish_ports, :integrations

    attr_reader :connections, :hooks, :optional_processes

    def self.load(root, global_path: default_global_path)
      config = new
      paths = [global_path, File.join(root, "config/rails_dev.rb"), File.join(root, "config/rails_dev.local.rb")]
      RailsDev.load_configuration(config, paths)
      config.validate!(root)
      config
    end

    def self.default_global_path
      File.join(ENV.fetch("XDG_CONFIG_HOME", File.join(Dir.home, ".config")), "rails-dev/config.rb")
    end

    def initialize
      @https = true
      @procfile = "Procfile.dev"
      @web = "web"
      @startup_timeout = 90
      @shutdown_timeout = 5
      @readiness = {}
      @http = {}
      @optional_processes = {}
      @env = {}
      @exclude_services = []
      @profiles = []
      @publish_ports = {}
      @integrations = []
      @connections = {}
      @hooks = HOOKS.to_h { |name| [name, []] }
    end

    HOOKS.each do |name|
      define_method(name) do |&callback|
        hooks.fetch(name) << callback if callback
        hooks.fetch(name)
      end
    end

    def http(name, **options)
      @http[name.to_s] = merge_options(@http.fetch(name.to_s, {}), options)
    end

    def endpoints
      defaults = { web.to_s => { port: 3000, env: "PORT", url_env: "RAILS_DEV_URL", readiness: { path: "/up" } } }
      defaults.merge(@http) { |_name, inherited, override| merge_options(inherited, override) }.map do |name, options|
        Endpoint.new(name, defaults: readiness, **options)
      end
    end

    def optional(process, with: process)
      @optional_processes[process.to_s] = with.to_s
      @integrations |= [with.to_s]
    end

    def enable_integrations(names)
      selected = Array(names).map(&:to_s)
      available = integrations.map(&:to_s)
      unknown = selected - available
      unless unknown.empty?
        raise Error, "Unknown integrations: #{unknown.join(", ")}. " \
                     "Available integrations: #{available.empty? ? "none" : available.join(", ")}."
      end

      @enabled_integrations = selected
    end

    def enabled?(name)
      Array(@enabled_integrations).include?(name.to_s)
    end

    def connect(service, port:, env:, protocol: "tcp")
      env.each do |variable, template|
        unless variable.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
          raise Error, "Invalid environment variable name: #{variable.inspect}."
        end

        tokens = template.scan(/%\{([^}]+)\}/).flatten
        raise Error, "#{variable}: use only %{host} and %{port} placeholders." unless (tokens - %w[host port]).empty?

        @connections[variable] = { service: service.to_s, port: port, protocol: protocol, value: template }
      end
    end

    def validate_connection_environment(env)
      return unless env["DATABASE_URL"] && connections.key?("PGPORT") && !connections.key?("DATABASE_URL")

      raise Error, "Unset DATABASE_URL or explicitly map it; it overrides the mapped PGPORT."
    end

    def validate!(root)
      validate_app!(root)
      validate_name!(root)
      if compose_file
        @compose_file = File.expand_path(compose_file, root)
        raise Error, "Compose file does not exist: #{compose_file}" unless File.file?(compose_file)
      end
      unless startup_timeout.positive? && shutdown_timeout.positive?
        raise Error, "Startup and shutdown timeouts must be positive."
      end

      endpoints
    end

    private

    def merge_options(inherited, overrides)
      inherited.merge(overrides) do |key, previous, value|
        key == :readiness && previous.is_a?(Hash) && value.is_a?(Hash) ? previous.merge(value) : value
      end
    end

    def validate_app!(root)
      %w[Gemfile bin/rails].each do |path|
        next if File.file?(File.join(root, path))

        raise Error, "Expected a Rails app; missing #{path} in #{root}."
      end
    end

    def validate_name!(root)
      @name ||= File.basename(root).downcase.gsub(/[^a-z0-9]+/, "-")[0, 45].gsub(/\A-|-\z/, "")
      return if name.match?(/\A[a-z0-9](?:[a-z0-9-]{0,43}[a-z0-9])?\z/)

      raise Error, "Set config.name to a hostname label of 1–45 lowercase letters, digits, or internal hyphens."
    end
  end
end
