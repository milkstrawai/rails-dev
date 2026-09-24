# frozen_string_literal: true

require "test_helper"
require "open3"

class ViteTest < Minitest::Test
  def test_uses_the_selected_https_origins
    server = configuration.fetch("config").fetch("server")

    assert_equal "https://laptop.example.ts.net:8443", server.fetch("origin")
    assert_equal({ "origin" => "https://laptop.example.ts.net" }, server.fetch("cors"))
    assert_equal ["laptop.example.ts.net"], server.fetch("allowedHosts")
    assert_equal({ "protocol" => "wss", "host" => "laptop.example.ts.net", "clientPort" => 8443 }, server.fetch("ws"))
  end

  def test_uses_default_https_ports_and_plain_http_ports
    https = configuration("RAILS_DEV_VITE_URL" => "https://assets.example.localhost")
    http = configuration("RAILS_DEV_VITE_URL" => "http://127.0.0.1:5174")

    assert_equal 443, https.dig("config", "server", "ws", "clientPort")
    assert_equal({ "protocol" => "ws", "host" => "127.0.0.1", "clientPort" => 5174 },
                 http.dig("config", "server", "ws"))
  end

  def test_metadata_and_cache_belong_to_the_run
    config = configuration

    assert_equal({ "devMetaFile" => "/tmp/rails-dev-run/rails-vite.json" }, config.fetch("rails"))
    assert_equal "/tmp/rails-dev-run/vite-cache", config.dig("config", "cacheDir")
    assert_equal "127.0.0.1", config.dig("config", "server", "host")
  end

  def test_cookie_names_follow_the_rails_port_and_survive_restarts
    original = configuration
    restarted = configuration("RAILS_DEV_RUNTIME" => "/tmp/restarted-run")
    concurrent = configuration("RAILS_PORT" => "3002")

    assert_equal '"rails-dev-3001-"', original.dig("config", "define", "import.meta.env.VITE_RAILS_DEV_COOKIE_PREFIX")
    assert_equal original.dig("config", "define"), restarted.dig("config", "define")
    refute_equal original.dig("config", "define"), concurrent.dig("config", "define")
  end

  def test_the_plugin_only_applies_during_development_serving
    assert_equal "serve", configuration.fetch("apply")
  end

  private

  def configuration(overrides = {})
    env = { "RAILS_DEV_RUNTIME" => "/tmp/rails-dev-run", "RAILS_PORT" => "3001",
            "RAILS_DEV_URL" => "https://laptop.example.ts.net",
            "RAILS_DEV_VITE_URL" => "https://laptop.example.ts.net:8443" }
    output, error, status = Open3.capture3(env.merge(overrides), "node", "test/fixtures/vite_configuration.mjs")

    assert_predicate status, :success?, error
    JSON.parse(output)
  end
end
