# frozen_string_literal: true

module RailsDev
  module CLI
    class Main < Base
      desc "setup", "Install the pinned Portless version, trust its CA, and start the shared HTTPS proxy"
      option :port, type: :numeric, default: 443, desc: "HTTPS proxy port"
      def setup
        Portless.new(Commands.new(root, output: shell.output)).setup(port: options[:port])
      end

      desc "doctor", "Check the shared proxy, certificates, and hostname resolution"
      def doctor
        Portless.new(Commands.new(root, output: shell.output)).doctor
      end

      desc "start", "Run the app's Procfile with available ports and HTTPS"
      option :with, type: :array, banner: "NAME [NAME...]", desc: "Enable optional integrations declared by the app"
      option :tailscale, type: :boolean, default: false, desc: "Share this run over HTTPS on your tailnet"
      def start
        config = configuration
        config.enable_integrations(options[:with])
        Session.new(root, config, tailscale: options[:tailscale], output: shell.output).start
      end

      desc "list", "List your active and interrupted instances across projects"
      def list
        selected_root = root if options[:root]
        runs = State.new.runs
        runs.select! { |run| run.fetch("root") == selected_root } if selected_root
        return say("No instances.") if runs.empty?

        rows = runs.flat_map { |run| instance_rows(run) }
        print_table([%w[INSTANCE APP PID STATUS CHECKOUT ENDPOINT URL], *rows], truncate: false)
      end

      desc "stop INSTANCE", "Stop one instance and recover its interrupted processes"
      def stop(instance)
        State.new.stop(instance, root: options[:root] ? root : nil)
        say "Stopped #{instance}."
      end

      desc "services COMMAND", "Manage Compose services and run host commands"
      subcommand "services", Services
      stop_on_unknown_option! :services

      no_commands do
        remove_method :services

        def services(*arguments)
          raise Thor::InvocationError, "Specify a command. See rails-dev services --help." if arguments.empty?

          Services.start(arguments, debug: true, shell: shell, class_options: options)
        end
      end

      private

      def instance_rows(run)
        urls = run.fetch("urls")
        urls = { "" => "" } if urls.empty?
        urls.each_with_index.map do |(name, url), index|
          fields = index.zero? ? run.values_at("id", "name", "pid", "status", "root") : Array.new(5, "")
          fields + [name, url]
        end
      end
    end
  end
end
