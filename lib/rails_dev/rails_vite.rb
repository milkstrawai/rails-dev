# frozen_string_literal: true

require "rails/railtie"

module RailsDev
  class RailsViteRailtie < Rails::Railtie
    # Inertia finds the Vite server through tmp/rails-vite.json, which each run moves. That file has the public URL,
    # so server rendering uses the loopback URL that vite.mjs saves instead.
    module InertiaSSR
      def vite_dev_server_url
        File.read(File.join(ENV.fetch("RAILS_DEV_RUNTIME"), "vite-loopback-url"))
      rescue Errno::ENOENT
        nil
      end

      # Vite belongs to this run, so the Puma plugin must not start a production SSR server, even before Vite listens.
      def vite_dev_server_running?
        true
      end
    end

    initializer "rails_dev.vite", before: :load_config_initializers do
      next unless Rails.env.development? && ENV.fetch("RAILS_DEV_RUNTIME", nil) && ENV["RAILS_DEV_VITE_URL"]

      RailsVite.config.dev_meta_path = Pathname.new(ENV.fetch("RAILS_DEV_RUNTIME")).join("rails-vite.json")
      RailsVite.config.auto_build = false
      InertiaRails::SSR.singleton_class.prepend(InertiaSSR) if defined?(InertiaRails::SSR)
    end
  end
end
