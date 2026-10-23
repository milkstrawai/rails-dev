require "json"
require "action_controller/railtie"
require "action_mailer/railtie"
require "rails_dev/railtie"
unless ENV["TEST_ERB"]
  require "rails_vite"
  require "inertia_rails" if ENV["TEST_INERTIA"]
  require "rails_dev/rails_vite" unless ENV["TEST_NO_VITE_HELPER"]
end

class TestApplication < Rails::Application
  config.root = File.expand_path("../../app", __dir__)
  config.eager_load = false
  config.secret_key_base = "test-secret" * 10
  config.logger = Logger.new(File::NULL)
  config.action_mailer.default_url_options = { host: "app.example", port: 3000, protocol: "http" }

  initializer "test_app.customize", after: :load_config_initializers do |app|
    next unless ENV["TEST_APP_OVERRIDE"]

    app.config.action_mailer.default_url_options = { host: "mailer.example" }
  end
end

Rails.application.initialize!
middleware = Rails.application.middleware.map(&:klass).map(&:name)
puts JSON.generate(
  metadata: defined?(RailsVite) && RailsVite.config.dev_meta_path.to_s,
  auto_build: defined?(RailsVite) && RailsVite.config.auto_build?,
  inertia_vite_url: defined?(InertiaRails) && InertiaRails::SSR.vite_dev_server_url,
  inertia_vite_running: defined?(InertiaRails) && InertiaRails::SSR.vite_dev_server_running?,
  hosts: Rails.application.config.hosts.map(&:to_s),
  mailer: Rails.application.config.action_mailer.default_url_options,
  routes: Rails.application.routes.default_url_options,
  middleware: middleware,
  mcp: ENV["MCP_ORIGIN"],
  launcher_loaded: defined?(RailsDev::Session)
)
