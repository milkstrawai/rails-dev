# frozen_string_literal: true

require "net/http"

module RailsDev
  class Portless
    VERSION = "0.15.6"

    attr_reader :url

    def initialize(commands)
      @commands = commands
      data = commands.env.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local/share"))
      @prefix = File.join(data, "rails-dev/portless", VERSION)
      @package = File.join(@prefix, "lib/node_modules/portless")
      @directory = File.expand_path(commands.env.fetch("PORTLESS_STATE_DIR", File.join(Dir.home, ".portless")))
      commands.env["PORTLESS_STATE_DIR"] = @directory
    end

    def setup(port: 443)
      raise Error, "Proxy port must be between 1 and 65535." unless (1..65_535).cover?(port)

      @commands.with_signals { install }
      @commands.env.merge!("PORTLESS_LAN" => "0", "PORTLESS_WILDCARD" => "0")
      @commands.replace([*cli, "service", "install", "--https", "--port", port.to_s, "--tld", "localhost"])
    end

    def install
      version = @commands.capture("node", "--version").delete_prefix("v").to_i
      raise Error, "Portless requires Node.js 24 or newer." if version < 24
      return if installed?

      @commands.run("npm", "install", "--global", "--prefix", @prefix,
                    "--ignore-scripts", "--no-audit", "--no-fund", "portless@#{VERSION}")
    end

    def doctor
      require_installation
      @commands.replace([*cli, "doctor"])
    end

    def check
      require_installation
      @url = URI(@commands.capture(*cli, "get", "rails-dev", "--no-worktree").strip)
      unless url.is_a?(URI::HTTPS) && url.host == "rails-dev.localhost"
        raise Error, "The shared Portless proxy must use HTTPS and .localhost. Run rails-dev setup."
      end

      verify_proxy
    end

    def start(name, endpoints:, web:)
      routes = endpoints.to_h do |endpoint|
        host = hostname(name, endpoint, web)
        endpoint.url = origin(host)
        [host, endpoint.port]
      end
      @commands.env["NODE_EXTRA_CA_CERTS"] ||= File.join(@directory, "ca.pem")
      yield @commands.start("https", ["node", File.join(__dir__, "portless.mjs"),
                                      File.join(@package, "dist/index.js"), @directory, JSON.generate(routes)],
                            ready_message: "HTTPS routes registered")
    end

    private

    def hostname(name, endpoint, web)
      label = "#{name}-#{web.port}"
      label += "-#{endpoint.name.downcase.tr("_", "-")}" unless endpoint == web
      "#{label}.localhost"
    end

    def cli
      ["node", File.join(@package, "dist/cli.js")]
    end

    def installed?
      path = File.join(@package, "package.json")
      File.file?(path) && JSON.parse(File.read(path))["version"] == VERSION
    end

    def require_installation
      return if installed?

      raise Error, "Portless #{VERSION} is not installed for rails-dev. Run rails-dev setup once on this machine."
    end

    def verify_proxy
      return if proxy_connection.get("/")["X-Portless"] == "1"

      raise Error, "The HTTPS listener is not Portless. Run rails-dev doctor."
    rescue SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout => error
      raise Error, "Cannot reach the HTTPS proxy: #{error.message}. Run rails-dev setup or rails-dev doctor."
    end

    def proxy_connection
      http = Net::HTTP.new(url.host, url.port, nil)
      http.ipaddr = "127.0.0.1"
      http.use_ssl = true
      http.ca_file = File.join(@directory, "ca.pem")
      http.open_timeout = http.read_timeout = 3
      http
    end

    def origin(host)
      uri = url.dup
      uri.host = host
      uri.to_s
    end
  end
end
