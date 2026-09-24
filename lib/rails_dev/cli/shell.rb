# frozen_string_literal: true

module RailsDev
  module CLI
    class Shell < Thor::Shell::Basic
      attr_reader :output

      def initialize(output, error)
        super()
        @output = output
        @error = error
      end

      private

      def stdout
        @output
      end

      def stderr
        @error
      end
    end
  end
end
