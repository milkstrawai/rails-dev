require "json"
require "socket"
require "fileutils"
STDOUT.sync = true
STDERR.sync = true

def record(event, extra = {})
  File.open(ENV.fetch("TEST_EVENTS"), "a") do |file|
    file.puts JSON.generate({event: event, pid: Process.pid}.merge(extra))
  end
end

role = ENV.fetch("TEST_ROLE", "rails")
if ARGV.first == "db:prepare"
  record("database", port: ENV["PGPORT"])
  exit
end
if ENV["TEST_FAIL_VITE"] == "1" && role == "vite"
  abort "A real configuration error"
end
if ENV["TEST_FAIL_RAILS"] == "1" && role == "rails"
  abort "A Rails configuration error"
end
if ENV["TEST_FAIL_PREPARE"] == "1"
  abort "Preparation failed"
end

port_option = ARGV.index("-p") || ARGV.index("--port")
port_variable = ENV.fetch("TEST_PORT_ENV", role == "rails" ? "PORT" : "VITE_PORT")
port = Integer(port_option ? ARGV.fetch(port_option + 1) : ENV.fetch(port_variable))
marker = File.join(Dir.pwd, "conflict-seen")
if ENV["TEST_BIND_CONFLICT"] == "1" && role == "rails" && !File.exist?(marker)
  File.write(marker, "waiting")
  record("bind_attempt", port: port, marker: marker)
  sleep 0.01 until File.read(marker) == "released"
end
server = TCPServer.new("127.0.0.1", port)
runtime = ENV["RAILS_DEV_RUNTIME"] || File.join(Dir.pwd, "tmp")
metadata = File.join(runtime, "rails-vite.json")
FileUtils.mkdir_p(runtime)
if role == "vite"
  url = ENV.fetch("RAILS_DEV_VITE_URL", "http://127.0.0.1:#{port}")
  File.write(metadata, JSON.generate(url: url, pid: Process.pid))
end
File.write(ENV.fetch("PIDFILE"), Process.pid) if role == "rails"
record("started", role: role, port: port, runtime: runtime, pidfile: ENV["PIDFILE"])
Signal.trap("TERM") { exit }
Signal.trap("INT") { exit }
at_exit do
  server.close
  FileUtils.rm_f(metadata) if role == "vite"
  record("stopped", role: role)
end
puts(role == "rails" ? "* Listening on http://127.0.0.1:#{port}" : "Local: http://127.0.0.1:#{port}/")
puts "startup output " * 5_000 if ENV["TEST_VERBOSE_STARTUP"] == "1"
loop do
  socket = server.accept
  method, path = socket.gets.split
  headers = {}
  while line = socket.gets
    break if line == "\r\n"
    key, value = line.strip.split(": ", 2)
    headers[key.downcase] = value
  end
  request_body = socket.read(headers.fetch("content-length", "0").to_i)
  record("request", method: method, path: path, headers: headers, body: request_body) if ENV["TEST_RECORD_REQUESTS"]
  vite_url = JSON.parse(File.read(metadata))["url"] if File.exist?(metadata)
  body = JSON.generate(role: role, pgport: ENV["PGPORT"], rails_port: ENV["RAILS_PORT"],
                       runtime: runtime, vite_url: vite_url, host: headers["host"], scheme: headers["x-forwarded-proto"])
  status = ENV.fetch("TEST_HTTP_STATUS", "200")
  status = "503" if ENV["TEST_READY_GATE"] && File.exist?(ENV["TEST_READY_GATE"])
  socket.write "HTTP/1.1 #{status} OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
  socket.close
end
