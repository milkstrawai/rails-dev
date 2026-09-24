RailsDev.configure do |config|
  config.http :web, port: 4000
  config.env["GLOBAL_SETTING"] = "inherited"
  config.integrations = %i[notifications]
end
