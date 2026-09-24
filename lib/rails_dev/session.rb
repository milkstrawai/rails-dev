# frozen_string_literal: true

require "English"
require "forwardable"

module RailsDev
  class Session
    extend Forwardable

    attr_reader :root, :runtime, :error

    def_delegators :@commands, :env, :run, :capture, :say, :check_for_interrupt
    def_delegator :@config, :enabled?

    def initialize(root, config, tailscale: false, output: $stdout)
      @root = root
      @config = config
      @tailscale = tailscale
      @commands = Commands.new(root, output: output, shutdown_timeout: config.shutdown_timeout + 1)
      @state = State.new(@commands)
      @hooks = Hooks.new(config, self)
    end

    def start
      @commands.with_signals do
        @state.with_run do |runtime|
          begin_run(runtime)
          prepare_environment
          @hooks.around { start_application }
        ensure
          @error = $ERROR_INFO
          stop
        end
      end
    end

    def url(name = @config.web)
      @endpoints&.find { |endpoint| endpoint.name == name.to_s }&.url
    end

    private

    def begin_run(runtime)
      @runtime = runtime
      @instance = Instance.new(runtime)
      @commands.instance = @instance
      record_run("starting", owner: ProcessTable.new.identity(Process.pid), processes: [],
                             shutdown_timeout: @config.shutdown_timeout + 1)
    end

    def record_run(status, **details)
      @instance.record(name: @config.name, root: root, pid: Process.pid, status: status,
                       urls: Array(@endpoints).to_h { |endpoint| [endpoint.name, endpoint.url] }, **details)
    end

    def prepare_environment
      env.merge!(@config.env)
      @config.validate_connection_environment(env) if @config.compose_file
      env.merge!("RAILS_ENV" => "development", "RACK_ENV" => "development", "RAILS_DEV_RUNTIME" => runtime,
                 "DEV_HOST" => "127.0.0.1", "PIDFILE" => File.join(runtime, "rails.pid"))
      @foreman = Foreman.new(root, @config)
      @endpoints = @foreman.endpoints
      prepare_proxy if @tailscale || @config.https
    end

    def prepare_proxy
      @proxy = (@tailscale ? Tailscale : Portless).new(@commands)
      @proxy.check
    end

    def start_application
      @state.synchronize("checkout:#{root}") do
        check_existing_rails
        prepare_services
        start_web
      end
      @hooks.call(:after_ready)
      report_ready
      supervise
    ensure
      @error = $ERROR_INFO
      @commands.stop
    end

    def check_existing_rails
      path = File.join(root, "tmp/pids/server.pid")
      return unless File.file?(path)

      pid = File.read(path).to_i
      return unless pid.positive?

      Process.kill(0, pid)
      raise Error, "Rails is already running for this checkout. Stop it before starting rails-dev."
    rescue Errno::ESRCH
      nil
    end

    def prepare_services
      if @config.compose_file
        compose = Compose.new(@config, @commands, @state, runtime)
        env.merge!(compose.start)
        @state.synchronize("database:#{compose.lock_key}") { @hooks.call(:before_start) }
      else
        @hooks.call(:before_start)
      end
    end

    def start_web
      @state.synchronize("web-ports") do
        5.times do
          ports = []
          @endpoints.each do |endpoint|
            endpoint.allocate(excluding: ports)
            ports << endpoint.port
          end
          return if launch_web

          @commands.say("A selected port was taken during startup; selecting ports again.")
          @commands.stop
        end
        raise Error, "Ports were repeatedly taken during startup. Try starting again."
      end
    end

    def launch_web
      @deadline = @commands.monotonic_time + @config.startup_timeout
      @processes = []
      web = @endpoints.find { |endpoint| endpoint.name == @config.web.to_s }
      @proxy&.start(@config.name, endpoints: @endpoints, web: web) do |process|
        @processes << process
        return false unless await_processes
      end
      start_foreman(web)
      await_processes(check_endpoints: true)
    end

    def start_foreman(web)
      @endpoints.each { |endpoint| env.merge!(endpoint.environment) }
      env.merge!("RAILS_PORT" => web.port.to_s, "RAILS_DEV_URL" => web.url)
      @application = @commands.start("foreman", @foreman.command, keep_stdin_open: true)
      @processes << @application
    end

    def await_processes(check_endpoints: false)
      loop do
        @commands.check_for_interrupt
        return false if startup_failed?
        return true if ready?(check_endpoints)

        raise Error, startup_timeout(check_endpoints) if @commands.monotonic_time >= @deadline

        sleep 0.05
      end
    end

    def startup_failed?
      failed = @processes.find { |process| !process.running? }
      return false unless failed
      return true if failed.startup_conflict? && (failed != @application || ports_taken?)

      process_failed(failed, "during startup")
    end

    def ports_taken?
      @endpoints.any? { |endpoint| Ports.available(endpoint.port) != endpoint.port }
    end

    def process_failed(process, phase)
      status = process.status.exitstatus || (128 + process.status.termsig)
      raise Error.new("#{process.name} exited #{phase} (#{process.exit_reason}). See its output above.",
                      status: status.zero? ? 1 : status)
    end

    def ready?(check_endpoints)
      @processes.all?(&:ready?) && (!check_endpoints || @endpoints.map { |endpoint| endpoint.ready?(@deadline) }.all?)
    end

    def startup_timeout(check_endpoints)
      pending = @processes.filter_map do |process|
        "#{process.name}: readiness message not received" unless process.ready?
      end
      pending.concat(@endpoints.filter_map(&:readiness_failure)) if check_endpoints
      ["Startup timed out after #{@config.startup_timeout}s.", *pending,
       "Check the process output and readiness settings."].join("\n")
    end

    def report_ready
      @commands.record_processes
      record_run("ready")
      @commands.say("Ready: #{url}")
      @endpoints.reject { |endpoint| endpoint.name == @config.web.to_s }.each do |endpoint|
        @commands.say("#{endpoint.name}: #{endpoint.url}")
      end
      @commands.say("Press Ctrl+C to stop the app processes.")
    end

    def supervise
      loop do
        @commands.check_for_interrupt
        failed = @processes.find { |process| !process.running? }
        return if failed == @application && failed.status.success?

        process_failed(failed, "while running") if failed
        sleep 0.05
      end
    end

    def stop
      @commands.stop
    ensure
      @error ||= $ERROR_INFO
      @hooks.after_stop(error)
    end
  end
end
