# frozen_string_literal: true

require "bundler"

module RailsDev
  class Commands
    attr_reader :env
    attr_writer :instance

    def initialize(root, output: $stdout, shutdown_timeout: 3)
      @root = root
      @output = Output.new(output)
      @env = Bundler.unbundled_env
      @children = []
      @shutdown_timeout = shutdown_timeout
    end

    def with_signals
      previous = %w[INT TERM HUP].to_h { |signal| [signal, Signal.trap(signal) { @signal = signal }] }
      yield
    ensure
      stop
      previous&.each { |signal, handler| Signal.trap(signal, handler) }
    end

    def run(*argv)
      execute(argv, stream: true)
    end

    def capture(*argv)
      execute(argv, stream: false)
    end

    def start(name, argv, stream: true, ready_message: nil, keep_stdin_open: false)
      check_for_interrupt
      child = Child.new(name, argv, env: env, root: @root, output: stream ? @output : nil,
                                    ready_message: ready_message, keep_stdin_open: keep_stdin_open)
      @children << child
      record_processes
      child
    end

    def replace(argv)
      Kernel.exec(env, [argv.first, argv.first], *argv.drop(1), chdir: @root, unsetenv_others: true)
    rescue Errno::ENOENT
      raise Error, "Command not found: #{argv.first}."
    end

    def stop(selected = @children.dup)
      return if selected.empty?

      selected.each { |child| child.signal("TERM") }
      wait_for_shutdown(selected)
      selected.each do |child|
        child.signal("KILL")
        child.reap
        child.close
        @children.delete(child)
      end
      record_processes
    end

    def record_processes
      @instance&.record_processes(@children.map(&:pid))
    end

    def check_for_interrupt
      return unless @signal

      signal = @signal
      @signal = nil
      raise Interrupted, signal
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def say(message)
      @output.puts("[rails-dev] #{message}")
    end

    def color?
      @output.tty? && env["NO_COLOR"].to_s.empty? && env["TERM"] != "dumb"
    end

    private

    def execute(argv, stream:)
      child = start(argv.first, argv, stream: stream)
      wait(child)
      raise Error, child.failure_message unless child.status.success?

      child.stdout
    ensure
      stop([child]) if child
    end

    def wait(child)
      while child.running?
        check_for_interrupt
        failed = @children.find { |other| other != child && !other.running? }
        raise Error, "#{failed.name} exited while running #{child.name} (#{failed.exit_reason})." if failed

        sleep 0.03
      end
      child.poll
      check_for_interrupt
    end

    def wait_for_shutdown(selected)
      deadline = monotonic_time + @shutdown_timeout
      until selected.none?(&:group_alive?) || monotonic_time >= deadline
        selected.each(&:poll)
        sleep 0.03
      end
    end
  end
end
