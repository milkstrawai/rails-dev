# frozen_string_literal: true

require "rails/railtie"
require "uri"
require_relative "cookies"

module RailsDev
  class Railtie < Rails::Railtie
    initializer "rails_dev.configure", before: :load_config_initializers do |app|
      next unless Rails.env.development? && ENV.key?("RAILS_DEV_RUNTIME") && ENV.key?("RAILS_DEV_URL")

      app.middleware.insert_before ActionDispatch::Cookies, Cookies, prefix: "rails-dev-#{ENV.fetch("RAILS_PORT")}-"

      origin = URI(ENV.fetch("RAILS_DEV_URL"))
      url_options = { host: origin.host, port: origin.port, protocol: origin.scheme }
      app.config.hosts << origin.host
      app.config.action_mailer.default_url_options = url_options
      app.routes.default_url_options.merge!(url_options)
    end
  end
end
