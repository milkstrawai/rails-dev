require "rails_dev"

state = RailsDev::State.new
details = JSON.parse(File.read(ARGV.fetch(0))).merge("pid" => Process.pid)
state.with_run do |runtime|
  RailsDev::Instance.new(runtime).record(**details)
  puts runtime
  $stdout.flush
  sleep
end
