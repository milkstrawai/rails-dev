RailsDev.configure do |config|
  config.compose_file = "dev-docker-compose.yml"
  config.connect "removed_service", port: 6379, env: { "REDIS_PORT" => "%{port}" }
end
