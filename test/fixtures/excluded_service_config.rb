RailsDev.configure do |config|
  config.compose_file = "dev-docker-compose.yml"
  config.exclude_services = ["postgres"]
end
