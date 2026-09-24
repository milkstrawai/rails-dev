# frozen_string_literal: true

module RailsDev
  class ServicePorts
    attr_reader :ports

    def initialize(services, config)
      @config = config
      @ports = services.to_h { |name, service| [name, service_ports(name, service)] }
      validate_connections
    end

    def override
      entries = ports.map do |name, mappings|
        "  #{name.to_json}:\n    ports: !override #{mappings.to_json}\n"
      end
      entries += @config.exclude_services.map { |name| "  #{name.to_json}: !reset null\n" }
      "services:\n#{entries.join}"
    end

    def environment(endpoints)
      @config.connections.to_h do |variable, mapping|
        endpoint = endpoints.fetch([mapping[:service], mapping[:port], mapping[:protocol]])
        value = mapping.fetch(:value).gsub("%{host}", endpoint.fetch(:host)).gsub("%{port}", endpoint.fetch(:port))
        [variable, value]
      end
    end

    private

    def service_ports(name, service)
      validate_service(name, service)
      declared = declared_ports(service)
      additional = @config.publish_ports.fetch(name, []).flat_map do |port|
        target, protocol = port.to_s.split("/", 2)
        expand(target, protocol || "tcp")
      end
      (declared + additional).uniq
    end

    def validate_service(name, service)
      if service["network_mode"] == "host" || service.fetch("scale", 1) != 1 ||
         service.dig("deploy", "replicas").to_i > 1
        raise Error, "#{name}: host networking and multiple replicas are not supported."
      end
    end

    def declared_ports(service)
      service.fetch("ports", []).flat_map do |port|
        expand(port.fetch("target"), port.fetch("protocol", "tcp"))
      end
    end

    def expand(target, protocol)
      match = /\A(\d+)(?:-(\d+))?\z/.match(target.to_s)
      raise Error, "Invalid container port: #{target}/#{protocol}." unless match && %w[tcp udp].include?(protocol)

      port_range(match).map { |port| { "target" => port, "host_ip" => "127.0.0.1", "protocol" => protocol } }
    end

    def port_range(match)
      first = match[1].to_i
      last = (match[2] || match[1]).to_i
      unless first.positive? && last >= first && last <= 65_535
        raise Error, "Invalid container port range: #{match[0]}."
      end

      first..last
    end

    def validate_connections
      validate_publications
      @config.connections.each do |variable, mapping|
        port = ports.fetch(mapping.fetch(:service), [])
        next if port.any? { |entry| entry["target"] == mapping[:port] && entry["protocol"] == mapping[:protocol] }

        raise Error, "#{variable}: mapped port is not published by an active service. " \
                     "Use Compose ports or publish_ports."
      end
    end

    def validate_publications
      @config.publish_ports.each_key do |name|
        raise Error, "Cannot publish ports for inactive or unknown service #{name.inspect}." unless ports.key?(name)
      end
    end
  end
end
