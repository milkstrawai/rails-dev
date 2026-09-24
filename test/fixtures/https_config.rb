RailsDev.configure do |config|
  config.name = "example"
  config.http :web, port: Integer(ENV.fetch("TEST_RAILS_PORT"))
  config.http :js, port: Integer(ENV.fetch("TEST_VITE_PORT")), env: "VITE_PORT", url_env: "RAILS_DEV_VITE_URL", readiness: "/@vite/client"
  config.compose_file = "dev-docker-compose.yml"
  config.connect "postgres", port: 5432, env: { "PGHOST" => "%{host}", "PGPORT" => "%{port}" }
end
