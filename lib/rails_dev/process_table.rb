# frozen_string_literal: true

require "open3"

module RailsDev
  class ProcessTable
    def initialize
      output, status = Open3.capture2({ "LC_ALL" => "C", "TZ" => "UTC0" },
                                      "ps", "-A", "-o", "pid=,pgid=,stat=,lstart=")
      raise Error, "Cannot inspect running processes." unless status.success?

      @entries = output.lines.filter_map do |line|
        pid, group, state, started = line.strip.split(/\s+/, 4)
        [pid.to_i, [pid.to_i, group.to_i, started]] unless state.start_with?("Z", "X")
      end.to_h
    rescue Errno::ENOENT
      raise Error, "Cannot inspect running processes: ps is unavailable."
    end

    def identity(pid)
      @entries[pid]
    end

    def include?(identity)
      identity && self.identity(identity.first) == identity
    end

    def members(groups)
      @entries.values.select { |entry| groups.include?(entry[1]) }
    end
  end
end
