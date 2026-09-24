# frozen_string_literal: true

module RailsDev
  class Child
    attr_reader :pid, :name, :stdout, :stderr, :status

    def initialize(name, argv, env:, root:, output: nil, ready_message: nil, keep_stdin_open: false)
      @name = name
      @output = output
      @stdout = +""
      @stderr = +""
      @readers = {}
      @ready_message = ready_message
      @ready = ready_message.nil?
      spawn(argv, env, root, keep_stdin_open)
    end

    def poll
      @readers.each { |reader, buffer| drain(reader, buffer) unless reader.closed? }
      @status ||= Process.waitpid2(pid, Process::WNOHANG)&.last
      @status
    end

    def running?
      poll.nil?
    end

    def ready?
      @ready
    end

    def failure_message
      detail = stderr.strip.empty? ? stdout.strip : stderr.strip
      ["#{name} failed (#{exit_reason}).", detail].reject(&:empty?).join("\n")
    end

    def exit_reason
      return "exit status #{status.exitstatus}" unless status.signaled?

      "signal #{Signal.signame(status.termsig) || status.termsig}"
    end

    def startup_conflict?
      output.match?(/EADDRINUSE|Address already in use|Port \d+ is already in use/i) ||
        (name.start_with?("tailscale-") &&
          output.match?(/listener already exists for port|Another client is changing the serve config/))
    end

    def reap
      @status ||= Process.waitpid2(pid).last
      poll
    end

    def group_alive?
      Process.kill(0, -pid)
      true
    rescue Errno::ESRCH
      false
    end

    def signal(value)
      Process.kill(value, -pid)
    rescue Errno::ESRCH
      nil
    end

    def output
      "#{stdout}\n#{stderr}"
    end

    def close
      @readers.each_key { |reader| reader.close unless reader.closed? }
      @input&.close
    end

    private

    def spawn(argv, env, root, keep_stdin_open)
      in_read, @input = IO.pipe if keep_stdin_open
      out_read, out_write = IO.pipe
      err_read, err_write = IO.pipe
      @readers = { out_read => @stdout, err_read => @stderr }
      command = [argv.first, argv.first]
      @pid = Process.spawn(env, command, *argv.drop(1), chdir: root, unsetenv_others: true, pgroup: true,
                                                        in: in_read || File::NULL, out: out_write, err: err_write)
    rescue Errno::ENOENT
      close
      raise Error, "Command not found: #{argv.first}. Make it available on PATH before starting rails-dev."
    ensure
      in_read&.close
      out_write&.close
      err_write&.close
    end

    def drain(reader, buffer)
      loop do
        chunk = reader.read_nonblock(8192, exception: false)
        break if chunk == :wait_readable
        return reader.close if chunk.nil?

        record_output(buffer, chunk)
      end
    end

    def record_output(buffer, chunk)
      buffer << chunk
      @ready ||= buffer.include?(@ready_message) if @ready_message
      @output&.write("[#{name}] #{chunk}")
      buffer.replace(buffer.byteslice(-32_768, 32_768)) if @output && buffer.bytesize > 32_768
    end
  end
end
