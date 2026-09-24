# frozen_string_literal: true

require "rbconfig"
require "net/http"

module CLIProcess
  def start_cli(extra_env = {}, prepare: false, arguments: nil, input: File::NULL, terminal: nil)
    @processes ||= []
    @output_paths ||= {}
    @output_path = File.join(@workspace, "cli-#{@output_paths.length}.log")
    env = Bundler.unbundled_env.merge(
      "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR),
      "PATH" => "#{fixture("tools")}:#{ENV.fetch("PATH")}",
      "XDG_STATE_HOME" => @workspace, "XDG_CONFIG_HOME" => @workspace,
      "TEST_EVENTS" => File.join(@workspace, "events.jsonl"),
      "DATABASE_URL" => nil
    ).merge(extra_env)
    command = arguments || ["start", "--root", @root, *(prepare ? ["--with", "prepare"] : [])]
    argv = [RbConfig.ruby, File.expand_path("../../exe/rails-dev", __dir__), *command]
    stdio = terminal ? { out: terminal, err: @output_path } : { out: @output_path, err: %i[child out] }
    pid = Process.spawn(env, *argv, unsetenv_others: true, in: input, **stdio)
    @processes << pid
    @output_paths[pid] = @output_path
    take_selected_port(pid) if extra_env["TEST_BIND_CONFLICT"] == "1"
    pid
  end

  def wait_until(pid = nil, timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      result = yield
      return result if result

      flunk "Timed out:\n#{output(pid)}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.02
    end
  end

  def output(pid = nil)
    File.read(pid ? @output_paths.fetch(pid) : @output_path)
  end

  def events
    path = File.join(@workspace, "events.jsonl")
    return [] unless File.exist?(path)

    File.readlines(path).filter_map do |line|
      JSON.parse(line) if line.end_with?("\n")
    end
  end

  def finish(pid, signal = "INT")
    Process.kill(signal, pid) if signal
    result = wait_until(pid) { Process.waitpid2(pid, Process::WNOHANG) }
    @processes.delete(pid)
    result.last
  end

  def kill_launcher(pid, runtime)
    details = JSON.parse(File.read(File.join(runtime, "instance.json")))
    (@abandoned ||= []).concat(details.fetch("processes"))
    finish(pid, "KILL")
  end

  def teardown
    @processes&.each { |pid| stop_process(pid) }
    stop_abandoned_processes
    @conflicts&.each(&:close)
  ensure
    super
  end

  private

  def ready_response(pid)
    wait_until(pid) { output(pid).include?("Ready:") }
    url = output(pid).match(%r{Ready: (http://127\.0\.0\.1:\d+)})[1]
    JSON.parse(Net::HTTP.get(URI(url)))
  end

  def take_selected_port(pid)
    attempt = wait_until(pid) { events.find { |event| event["event"] == "bind_attempt" } }
    (@conflicts ||= []) << TCPServer.new("127.0.0.1", attempt.fetch("port"))
    File.write(attempt.fetch("marker"), "released")
  end

  def stop_process(pid)
    Process.kill("TERM", pid)
    waiter = Process.detach(pid)
    return if waiter.join(5)

    Process.kill("KILL", pid)
    flunk "Could not stop process #{pid}:\n#{output(pid)}" unless waiter.join(5)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def stop_abandoned_processes
    @abandoned&.each do |identity|
      Process.kill("KILL", -identity[1]) if RailsDev::ProcessTable.new.include?(identity)
    rescue Errno::ESRCH
      nil
    end
  end
end
