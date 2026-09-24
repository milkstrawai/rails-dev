# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"

module RailsDev
  class State
    attr_reader :directory

    def initialize(commands = nil, base: ENV.fetch("XDG_STATE_HOME", File.join(Dir.home, ".local/state")))
      @commands = commands
      @directory = File.join(base, "rails-dev")
    end

    def with_run
      FileUtils.mkdir_p(directory, mode: 0o700)
      Dir.mktmpdir("run-", directory) do |runtime|
        File.open(File.join(runtime, "owner.lock"), File::RDWR | File::CREAT, 0o600) do |owner|
          owner.flock(File::LOCK_EX)
          FileUtils.cp(File.join(__dir__, "vite.mjs"), File.join(runtime, "vite.mjs"))
          yield runtime
        end
      end
    end

    def runs
      instances.filter_map(&:snapshot)
               .sort_by { |run| run.values_at("name", "root", "pid") }
    end

    def stop(id, root: nil)
      instance = instances.find { |run| run.id == id }
      if !instance || (root && instance.snapshot&.fetch("root") != root)
        raise Error, "Unknown instance: #{id}. See rails-dev list."
      end

      synchronize("stop:#{id}") { instance.stop }
    end

    def synchronize(key)
      FileUtils.mkdir_p(directory, mode: 0o700)
      path = File.join(directory, "#{Digest::SHA256.hexdigest(key)}.lock")
      File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
        until file.flock(File::LOCK_EX | File::LOCK_NB)
          @commands&.check_for_interrupt
          sleep 0.05
        end
        yield
      end
    end

    private

    def instances
      Dir.glob(File.join(directory, "run-*/instance.json")).map { |path| Instance.new(File.dirname(path)) }
    end
  end
end
