# frozen_string_literal: true

require "test_helper"
require "open3"

class RailtieTest < Minitest::Test
  def test_managed_development_uses_its_own_metadata_and_cookies
    config = boot

    assert_equal "/tmp/rails-dev-run/rails-vite.json", config.fetch("metadata")
    middleware = config.fetch("middleware")

    assert_operator middleware.index("RailsDev::Cookies"), :<, middleware.index("ActionDispatch::Cookies")
  end

  def test_managed_development_uses_the_public_origin
    config = boot
    origin = { "host" => "laptop.example.ts.net", "port" => 8444, "protocol" => "https" }

    assert_includes config.fetch("hosts"), "laptop.example.ts.net"
    assert_equal origin, config.fetch("mailer")
    assert_equal origin, config.fetch("routes")
  end

  def test_erb_apps_do_not_need_vite
    config = boot("TEST_ERB" => "1", "RAILS_DEV_VITE_URL" => nil)

    assert_nil config.fetch("metadata")
    assert_includes config.fetch("middleware"), "RailsDev::Cookies"
    assert_includes config.fetch("hosts"), "laptop.example.ts.net"
  end

  def test_installed_vite_does_not_activate_its_helper
    config = boot("TEST_NO_VITE_HELPER" => "1")

    assert_match %r{/tmp/rails-vite\.json\z}, config.fetch("metadata")
  end

  def test_managed_vite_does_not_build_assets_while_the_dev_server_boots
    refute boot.fetch("auto_build")
  end

  def test_inertia_renders_through_the_runs_vite_server_over_loopback
    Dir.mktmpdir do |runtime|
      File.write(File.join(runtime, "vite-loopback-url"), "http://127.0.0.1:5174")

      assert_equal "http://127.0.0.1:5174",
                   boot("TEST_INERTIA" => "1", "RAILS_DEV_RUNTIME" => runtime).fetch("inertia_vite_url")
    end
  end

  def test_inertia_does_not_start_its_own_ssr_server_before_vite_listens
    config = boot("TEST_INERTIA" => "1")

    assert_nil config.fetch("inertia_vite_url")
    assert config.fetch("inertia_vite_running")
  end

  def test_normal_development_keeps_inertia_vite_detection
    refute boot("TEST_INERTIA" => "1", "RAILS_DEV_RUNTIME" => nil).fetch("inertia_vite_running")
  end

  def test_normal_development_keeps_app_defaults
    config = boot("RAILS_DEV_RUNTIME" => nil)

    assert_equal({ "host" => "app.example", "port" => 3000, "protocol" => "http" }, config.fetch("mailer"))
    refute_includes config.fetch("middleware"), "RailsDev::Cookies"
    assert_match %r{/tmp/rails-vite\.json\z}, config.fetch("metadata")
  end

  def test_preparation_can_boot_before_the_launcher_selects_ports
    config = boot("RAILS_DEV_URL" => nil, "RAILS_PORT" => nil)

    assert_equal({ "host" => "app.example", "port" => 3000, "protocol" => "http" }, config.fetch("mailer"))
    refute_includes config.fetch("middleware"), "RailsDev::Cookies"
  end

  def test_app_initializers_can_override_the_defaults
    assert_equal({ "host" => "mailer.example" }, boot("TEST_APP_OVERRIDE" => "1").fetch("mailer"))
  end

  def test_production_ignores_inherited_launcher_settings
    config = boot("RAILS_ENV" => "production")

    refute_includes config.fetch("hosts"), "laptop.example.ts.net"
    refute_includes config.fetch("middleware"), "RailsDev::Cookies"
    assert_empty config.fetch("routes")
  end

  def test_the_adapter_does_not_load_the_launcher_or_app_specific_settings
    config = boot

    assert_nil config.fetch("mcp")
    assert_nil config.fetch("launcher_loaded")
  end

  private

  def boot(overrides = {})
    env = { "RAILS_ENV" => "development", "RAILS_DEV_RUNTIME" => "/tmp/rails-dev-run",
            "RAILS_PORT" => "3001", "RAILS_DEV_URL" => "https://laptop.example.ts.net:8444",
            "RAILS_DEV_VITE_URL" => "https://laptop.example.ts.net:8445", "MCP_ORIGIN" => nil }
    output, error, status = Open3.capture3(env.merge(overrides), RbConfig.ruby, "-Ilib",
                                           "test/fixtures/rails/application.rb")

    assert_predicate status, :success?, error
    JSON.parse(output)
  end
end
