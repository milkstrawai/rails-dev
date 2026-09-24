# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  include TestWorkspace

  def test_compose_is_optional_even_when_a_file_exists
    config = RailsDev::Configuration.load(@root, global_path: "/nonexistent")

    assert_nil config.compose_file
  end

  def test_app_and_local_configuration_override_global_defaults
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("app_config.rb"), File.join(@root, "config/rails_dev.rb"))
    FileUtils.cp(fixture("local_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    config = RailsDev::Configuration.load(@root, global_path: fixture("global_config.rb"))

    assert_equal 4200, config.endpoints.find { |endpoint| endpoint.name == "web" }.port
    assert_equal "inherited", config.env.fetch("GLOBAL_SETTING")
  end

  def test_app_and_local_configuration_control_available_integrations
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("app_config.rb"), File.join(@root, "config/rails_dev.rb"))
    FileUtils.cp(fixture("local_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    config = RailsDev::Configuration.load(@root, global_path: fixture("global_config.rb"))
    config.enable_integrations(%w[worker helper])

    assert config.enabled?(:worker)
    assert config.enabled?("helper")
    assert_raises(RailsDev::Error) { config.enable_integrations(["notifications"]) }
  end

  def test_uses_only_the_explicit_compose_file
    FileUtils.cp(File.join(@root, "dev-docker-compose.yml"), File.join(@root, "compose.yaml"))

    config = RailsDev::Configuration.new
    config.compose_file = "compose.yaml"
    config.validate!(@root)

    assert_equal File.join(@root, "compose.yaml"), config.compose_file
  end

  def test_app_hooks_extend_global_hooks
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("app_hook_config.rb"), File.join(@root, "config/rails_dev.rb"))
    config = RailsDev::Configuration.load(@root, global_path: fixture("global_hook_config.rb"))
    events = []
    config.before_start.each { |callback| callback.call(events) }

    assert_equal %i[global app], events
  end

  def test_local_config_can_replace_one_inherited_hook_list
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.cp(fixture("app_hook_config.rb"), File.join(@root, "config/rails_dev.rb"))
    FileUtils.cp(fixture("local_hook_config.rb"), File.join(@root, "config/rails_dev.local.rb"))
    config = RailsDev::Configuration.load(@root, global_path: fixture("global_hook_config.rb"))
    events = []
    config.before_start.each { |callback| callback.call(events) }
    config.after_ready.each { |callback| callback.call(events) }

    assert_equal %i[local global_ready], events
  end

  def test_uses_https_and_a_name_from_the_checkout_by_default
    config = RailsDev::Configuration.load(@root, global_path: "/nonexistent")

    assert config.https
    assert_equal "app", config.name
  end

  def test_rejects_a_name_that_cannot_be_used_in_an_instance_hostname
    config = RailsDev::Configuration.new
    config.name = "invalid.name"

    error = assert_raises(RailsDev::Error) { config.validate!(@root) }

    assert_includes error.message, "config.name"
  end
end
