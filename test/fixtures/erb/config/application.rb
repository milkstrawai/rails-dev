require_relative "boot"
require "rails"
require "action_controller/railtie"
require "action_mailer/railtie"
Bundler.require(*Rails.groups)

module ErbFixture
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
    config.secret_key_base = "test-secret" * 10
    config.logger = Logger.new(File::NULL)
  end
end
