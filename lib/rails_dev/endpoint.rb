# frozen_string_literal: true

require "net/http"

module RailsDev
  class Endpoint
    attr_reader :name, :port
    attr_accessor :url

    def initialize(name, port:, env:, url_env: "RAILS_DEV_#{name.upcase.tr("-", "_")}_URL", readiness: false,
                   defaults: {})
      @name = name
      @port = port
      @preferred_port = port
      @variable = env
      @url_variable = url_env
      @check = readiness
      @options = { path: "/" }.merge(defaults).merge(readiness.is_a?(Hash) ? readiness : { path: readiness })
      return if port.is_a?(Integer) && (1024..65_535).cover?(port)

      raise Error, "#{name}: port must be an integer between 1024 and 65535."
    end

    def allocate(excluding: [])
      @port = Ports.available(@preferred_port, excluding: excluding)
      @url = "http://127.0.0.1:#{port}"
      @ready = @started = @next_check = @last_failure = nil
    end

    def environment
      { @variable => port.to_s, @url_variable => url }
    end

    def ready?(deadline)
      return true if @ready || !@check

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @started ||= now
      remaining = remaining_time(now, deadline)
      return false if @next_check && now < @next_check

      @next_check = now + @options.fetch(:interval, 0.1)
      @ready = check(remaining)
    end

    def readiness_failure
      return if @ready || !@check

      target = if @check.respond_to?(:call)
                 "custom readiness check"
               else
                 path = @options.fetch(:path).to_s.split(/[?#]/, 2).first
                 "#{@options.fetch(:method, "GET").upcase} http://127.0.0.1:#{port}#{path}"
               end
      "#{name} (#{target}): #{@last_failure || "not checked yet"}"
    end

    private

    def remaining_time(now, deadline)
      remaining = [deadline, @started + @options.fetch(:timeout, Float::INFINITY)].min - now
      unless remaining.positive?
        raise Error, "Startup timed out: #{readiness_failure}. Check the process output and readiness settings."
      end

      remaining
    end

    def check(remaining)
      @last_failure = "check did not pass" if @check.respond_to?(:call)
      @check.respond_to?(:call) ? @check.call(self) : healthy_response?(remaining)
    rescue Error
      raise
    rescue StandardError => error
      raise Error, "#{name} readiness check failed: #{error.message}"
    end

    def healthy_response?(remaining)
      response = connection(remaining).request(request, @options[:body])
      successful_response?(response)
    rescue SystemCallError, IOError, Timeout::Error, Net::ProtocolError => error
      @last_failure = "request failed (#{error.class})"
      false
    end

    def successful_response?(response)
      success = @options.fetch(:success, 200)
      expected = success.respond_to?(:call) ? "a passing custom success check" : Array(success).join(" or ")
      @last_failure = "HTTP #{response.code}; expected #{expected}"
      success.respond_to?(:call) ? success.call(response) : Array(success).include?(response.code.to_i)
    end

    def connection(remaining)
      http = Net::HTTP.new("127.0.0.1", port, nil)
      http.open_timeout = http.read_timeout = http.write_timeout = [@options.fetch(:request_timeout, 1), remaining].min
      http
    end

    def request
      method = @options.fetch(:method, "GET").upcase
      headers = { "Host" => URI(url).host }.merge(@options.fetch(:headers, {}))
      Net::HTTPGenericRequest.new(method, !@options[:body].nil?, method != "HEAD", @options.fetch(:path), headers)
    end
  end
end
