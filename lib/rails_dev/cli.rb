# frozen_string_literal: true

require "thor"

module RailsDev
  module CLI
    class << self
      def run(argv, output: $stdout, error: $stderr)
        output = Output.new(output)
        shell = Shell.new(output, Output.new(error))
        validate_arguments(argv)
        Main.start(argv, debug: true, shell: shell)
        0
      rescue Interrupted => error
        output.puts("[rails-dev] #{error.message}")
        128 + Signal.list.fetch(error.signal)
      rescue Error, Thor::Error, Errno::ENOENT => error
        shell.error("rails-dev: #{error.message}")
        error.is_a?(Error) ? error.status : 1
      end

      private

      def validate_arguments(argv)
        raise Thor::InvocationError, "Specify a command. See rails-dev --help." if argv.empty?

        options = argv.take_while { |argument| argument != "--" }
        options.each_with_index do |argument, index|
          next unless argument == "--root"

          value = options[index + 1]
          if value.nil? || value.start_with?("-")
            raise Thor::MalformattedArgumentError, "No value provided for option '--root'"
          end
        end
      end
    end
  end
end

require_relative "cli/shell"
require_relative "cli/base"
require_relative "cli/services"
require_relative "cli/main"
