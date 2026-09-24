require "json"
File.write(ENV.fetch("TEST_RESULT"), JSON.generate(
  "argv" => ARGV,
  "rails_env" => ENV["RAILS_ENV"],
  "pgport" => ENV["PGPORT"],
  "pidfile" => ENV["PIDFILE"],
  "stdin" => (STDIN.read if ENV["TEST_READ_STDIN"])
))
exit Integer(ENV.fetch("TEST_EXIT", "0"))
