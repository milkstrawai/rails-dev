RailsDev.configure do |config|
  config.procfile = "Procfile.integrations"
  config.optional :worker
  config.optional :helper

  config.before_start do |run|
    run.env["TEST_INTEGRATION"] = "worker" if run.enabled?(:worker)
  end
end
