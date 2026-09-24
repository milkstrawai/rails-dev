RailsDev.configure do |config|
  config.procfile = "Procfile.processes"
  config.optional :helper unless ENV["TEST_TWO_PROCESSES"] == "1"
  config.after_ready do
    raise "Hook failed after starting a process" if ENV["TEST_FAIL_AFTER_PROCESS"] == "1"
  end
end
