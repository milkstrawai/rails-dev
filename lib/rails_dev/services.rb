# frozen_string_literal: true

require "tmpdir"

module RailsDev
  class Services
    def initialize(root, config, output: $stdout)
      @config = config
      @commands = Commands.new(root, output: output)
      @state = State.new(@commands)
    end

    def run(action, argv = [])
      @commands.with_signals do
        @commands.env.merge!(@config.env)
        manage(action) if @config.compose_file
        raise Error, "Set config.compose_file to manage Compose services." if !@config.compose_file && action != "exec"
      end
      @commands.replace(argv) if action == "exec"
    end

    private

    def manage(action)
      @config.validate_connection_environment(@commands.env) unless action == "stop"
      FileUtils.mkdir_p(@state.directory, mode: 0o700)
      Dir.mktmpdir("services-", @state.directory) do |runtime|
        compose = Compose.new(@config, @commands, @state, runtime)
        if action == "stop"
          compose.stop
        else
          @commands.env.merge!(compose.start)
        end
      end
    end
  end
end
