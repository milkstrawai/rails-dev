RailsDev.configure do |config|
  config.http :web, port: 4200
  config.integrations << "helper"
end
