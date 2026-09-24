RailsDev.configure do |config|
  config.http :web, port: 4100
  config.integrations = %i[worker]
end
