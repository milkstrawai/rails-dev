# frozen_string_literal: true

module RailsDev
  class Cookies
    def initialize(app, prefix:)
      @app = app
      @prefix = prefix
    end

    def call(env)
      env["HTTP_COOKIE"] = env.fetch("HTTP_COOKIE", "").split(/;\s*/).filter_map do |cookie|
        cookie.delete_prefix(@prefix) if cookie.start_with?(@prefix)
      end.join("; ")

      status, headers, body = @app.call(env)
      if headers["set-cookie"]
        headers["set-cookie"] = Array(headers["set-cookie"]).map { |cookie| "#{@prefix}#{cookie}" }
      end
      [status, headers, body]
    end
  end
end
