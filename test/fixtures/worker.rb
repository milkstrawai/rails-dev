require "json"
require "socket"
STDOUT.sync = true
STDERR.sync = true

case ARGV.shift
when "capture"
  puts JSON.generate("argument" => ARGV.fetch(0), "bundle" => ENV["BUNDLE_GEMFILE"])
  warn "diagnostic"
when "failure"
  warn "database is unavailable"
  exit 7
when "stdout_failure"
  puts "service is unavailable"
  exit 7
when "mixed_failure"
  puts "captured value"
  warn "authentication failed"
  exit 3
when "terminated"
  Process.kill("TERM", Process.pid)
when "stubborn"
  Signal.trap("TERM") { puts "Still running" }
  puts "Ready"
  sleep
when "stubborn-tree"
  reader, writer = IO.pipe
  child = fork do
    reader.close
    Signal.trap("TERM", "IGNORE")
    writer.puts "Ready"
    writer.close
    sleep
  end
  writer.close
  reader.gets
  reader.close
  Signal.trap("TERM") { exit }
  puts child
  sleep
when "tree"
  child = fork do
    Signal.trap("TERM") { exit }
    sleep
  end
  puts child
  Signal.trap("TERM") do
    Process.wait(child)
    exit
  end
  sleep
end
