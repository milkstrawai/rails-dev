require "json"
STDOUT.sync = true
STDERR.sync = true

def record(event, extra = {})
  File.open(ENV.fetch("TEST_EVENTS"), "a") do |file|
    file.puts JSON.generate({event: event, pid: Process.pid, runtime: ENV["RAILS_DEV_RUNTIME"]}.merge(extra))
  end
end

name = ARGV.shift
Signal.trap("INT") { exit }
Signal.trap("TERM") { exit }
descendant = nil
at_exit do
  Process.wait(descendant) if descendant
  record("process_stopped", name: name)
end
record("process_started", name: name, arguments: ARGV, root: Dir.pwd, pgport: ENV["PGPORT"],
                          rails_port: ENV["RAILS_PORT"], url: ENV["RAILS_DEV_URL"])
if ENV["TEST_PROCESS_FAIL"] == "1"
  warn "Worker configuration failed"
  exit 23
end
if ENV["TEST_PROCESS_TREE"] == "1"
  descendant = fork { sleep }
  record("process_descendant", descendant: descendant)
end
if ENV["TEST_PROCESS_GATE"]
  sleep 0.02 while File.exist?(ENV["TEST_PROCESS_GATE"])
end
puts "Worker ready" unless ENV["TEST_PROCESS_NO_MARKER"] == "1"
sleep
