# frozen_string_literal: true

module RailsDev
  module CLI
    class Services < Base
      desc "start", "Start or reuse Compose services"
      def start
        run("start")
      end

      desc "stop", "Stop Compose services, keeping containers and volumes"
      def stop
        run("stop")
      end

      desc "exec -- COMMAND [ARGS]", "Run a host command with service connection settings"
      def exec(command, *arguments)
        run("exec", [command, *arguments])
      end

      private

      def run(action, arguments = [])
        RailsDev::Services.new(root, configuration, output: shell.output).run(action, arguments)
      end
    end
  end
end
