# frozen_string_literal: true

require "uri"

module RailsDev
  class Tailscale
    def initialize(commands)
      @commands = commands
    end

    def check
      status = JSON.parse(@commands.capture("tailscale", "status", "--json"))
      node = status["Self"] || {}
      @hostname = node.fetch("DNSName", "").delete_suffix(".")
      unless status["BackendState"] == "Running" && !@hostname.empty?
        raise Error, "Connect Tailscale before using --tailscale. Run tailscale status."
      end

      return if https_enabled?(node)

      raise Error, "Enable HTTPS certificates in your tailnet's DNS settings before using --tailscale."
    end

    def start(_name, endpoints:, **)
      endpoints.zip(available_ports(endpoints.size)).each do |endpoint, https|
        endpoint.url = origin(https)
        yield @commands.start("tailscale-#{endpoint.name}",
                              ["tailscale", "serve", "--bg=false", "--https=#{https}", "http://127.0.0.1:#{endpoint.port}"],
                              ready_message: "Press Ctrl+C to exit.")
      end
    end

    private

    def https_enabled?(node)
      capabilities = Array(node["Capabilities"]) + node.fetch("CapMap", {}).keys
      capabilities.any? { |capability| capability == "https" || capability.end_with?("/https") }
    end

    def available_ports(count)
      config = JSON.parse(@commands.capture("tailscale", "serve", "status", "--json"))
      used = [config, *config.fetch("Foreground", {}).values].flat_map { |entry| used_ports(entry) }
      ports = [443].chain(8443..65_535).lazy.reject { |port| used.include?(port) }.take(count).to_a
      raise Error, "Tailscale needs #{count} available HTTPS ports." unless ports.size == count

      ports
    end

    def used_ports(config)
      config.fetch("TCP", {}).keys.map(&:to_i) + config.fetch("AllowFunnel", {}).filter_map do |host, enabled|
        host.split(":").last.to_i if enabled
      end
    end

    def origin(port)
      URI::HTTPS.build(host: @hostname, port: port).to_s
    end
  end
end
