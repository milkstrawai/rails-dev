# frozen_string_literal: true

require "rails/railtie"

module RailsDev
  class RailsViteRailtie < Rails::Railtie
    initializer "rails_dev.vite", before: :load_config_initializers do
      next unless Rails.env.development? && ENV.fetch("RAILS_DEV_RUNTIME", nil) && ENV["RAILS_DEV_VITE_URL"]

      RailsVite.config.dev_meta_path = Pathname.new(ENV.fetch("RAILS_DEV_RUNTIME")).join("rails-vite.json")
      RailsVite.config.auto_build = false
    end
  end
end
