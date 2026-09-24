require "json"

name = ARGV.fetch(0)
File.open(ENV.fetch("TEST_EVENTS"), "a") do |file|
  file.puts JSON.generate(event: "hook_command", name: name, root: Dir.pwd, runtime: ENV["RAILS_DEV_RUNTIME"],
                         url: ENV["RAILS_DEV_URL"], pgport: ENV["PGPORT"], pid: Process.pid)
end
if ENV["TEST_HOOK_GATE_AT"] == name
  sleep 0.02 while File.exist?(ENV.fetch("TEST_HOOK_GATE"))
end
