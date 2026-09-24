# frozen_string_literal: true

module RailsDev
  module CLI
    class Base < Thor
      def self.exit_on_failure?
        true
      end

      remove_command :tree
      check_unknown_options!

      class_option :root, type: :string, banner: "PATH",
                          desc: "App directory (default: current directory; list/stop: all projects)"
      class_option :help, type: :boolean, aliases: "-h", desc: "Show help"
      class_option :version, type: :boolean, aliases: "-v", desc: "Print version"

      no_commands do
        def invoke_command(command, *arguments)
          if options[:version]
            say VERSION
          elsif options[:help]
            help(command.name == "help" ? nil : command.name)
          else
            super
          end
        end
      end

      private

      def root
        @root ||= File.realpath(options[:root] || Dir.pwd)
      end

      def configuration
        Configuration.load(root)
      end
    end
  end
end
