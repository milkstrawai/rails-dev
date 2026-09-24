# frozen_string_literal: true

module RailsDev
  class Instance
    def initialize(directory)
      @directory = directory
      @path = File.join(directory, "instance.json")
    end

    def id
      File.basename(@directory)
    end

    def record(**details)
      data = File.file?(@path) ? read : {}
      File.write("#{@path}.tmp", JSON.generate(data.merge(details.transform_keys(&:to_s))), perm: 0o600)
      File.rename("#{@path}.tmp", @path)
    end

    def record_processes(groups)
      record(processes: ProcessTable.new.members(groups))
    end

    def snapshot
      File.open(File.join(@directory, "owner.lock")) do |owner|
        data = read.merge("id" => id)
        data["status"] = interrupted_status(data) if owner.flock(File::LOCK_EX | File::LOCK_NB)
        data
      end
    rescue Errno::ENOENT
      nil
    end

    def stop
      File.open(File.join(@directory, "owner.lock")) do |owner|
        stop_owner(owner)
        recover if File.file?(@path)
      end
    rescue Errno::ENOENT
      nil
    end

    private

    def read
      JSON.parse(File.read(@path))
    end

    def interrupted_status(data)
      records = data["processes"]
      return "interrupted" unless records

      table = ProcessTable.new
      return "orphaned" if records.any? { |identity| table.include?(identity) }

      table.members(process_groups(records)).empty? ? "stale" : "interrupted"
    end

    def process_groups(records)
      records.map { |identity| identity[1] }.uniq
    end

    def stop_owner(owner)
      return if owner.flock(File::LOCK_EX | File::LOCK_NB)

      timeout = read.fetch("shutdown_timeout", 5)
      signal_owner(owner, "TERM")
      return if wait(timeout + 2) { owner.flock(File::LOCK_EX | File::LOCK_NB) }

      signal_owner(owner, "KILL")
      return if wait(2) { owner.flock(File::LOCK_EX | File::LOCK_NB) }

      raise Error, "Instance #{id} is still stopping; retry with rails-dev stop #{id}."
    end

    def signal_owner(owner, signal)
      data = read
      identity = data["owner"]
      if ProcessTable.new.include?(identity)
        signal(signal, identity.first)
      elsif !owner.flock(File::LOCK_EX | File::LOCK_NB)
        raise Error, recovery_error("Cannot verify the launcher for #{id} (PID #{data.fetch("pid")}). " \
                                    "Stop it from its original terminal.")
      end
    end

    def recovery_error(message)
      "#{message}\nInspect #{@path} and verify process ownership before manual cleanup."
    end

    def recover
      data = read
      @records = data.fetch("processes") do
        raise Error, recovery_error("Cannot recover #{id}: process ownership was not recorded.")
      end
      @records = verified_members
      record(processes: @records)
      stop_groups(data.fetch("shutdown_timeout", 5))
      FileUtils.remove_entry(@directory)
    end

    def verified_members
      table = ProcessTable.new
      members = table.members(process_groups(@records))
      verified = process_groups(@records.select { |identity| table.include?(identity) })
      unverified = process_groups(members) - verified
      unless unverified.empty?
        raise Error, recovery_error("Cannot verify process groups #{unverified.join(", ")} for #{id}. " \
                                    "Recovery record kept.")
      end

      members
    end

    def stop_groups(timeout)
      signal_groups("TERM")
      return if wait(timeout) { verified_members.empty? }

      signal_groups("KILL")
      return if wait(2) { verified_members.empty? }

      raise Error, "Instance #{id} is still stopping; retry with rails-dev stop #{id}."
    end

    def signal_groups(value)
      process_groups(verified_members).each { |group| signal(value, -group) }
    end

    def signal(value, pid)
      Process.kill(value, pid)
    rescue Errno::ESRCH
      nil
    end

    def wait(timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        return true if yield
        return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.05
      end
    end
  end
end
