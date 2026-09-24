RailsDev.configure do |config|
  config.https = false
  config.compose_file = "dev-docker-compose.yml"
  config.connect "postgres", port: 5432, env: { "PGHOST" => "%{host}", "PGPORT" => "%{port}" }
end
