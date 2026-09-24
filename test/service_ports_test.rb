# frozen_string_literal: true

require "test_helper"

class ServicePortsTest < Minitest::Test
  def setup
    super
    @services = JSON.parse(File.read(File.join(__dir__, "fixtures/services-model.json"))).fetch("services")
    @config = RailsDev::Configuration.new
  end

  def test_replaces_all_declared_ports_with_loopback_bindings
    plan = RailsDev::ServicePorts.new(@services, @config)

    assert_equal([8123, 9000], plan.ports.fetch("clickhouse").map { |port| port["target"] })
    assert_equal "udp", plan.ports.fetch("dns").first.fetch("protocol")
    assert(plan.ports.values.flatten.all? { |port| port["host_ip"] == "127.0.0.1" && !port.key?("published") })
  end

  def test_internal_ports_stay_internal_unless_explicitly_published
    assert_empty RailsDev::ServicePorts.new(@services, @config).ports.fetch("internal")
    @config.publish_ports["internal"] = [8080]

    assert_equal 8080, RailsDev::ServicePorts.new(@services, @config).ports.fetch("internal").first.fetch("target")
  end

  def test_exclusions_remove_the_service_from_the_override
    @config.exclude_services = ["debug"]
    plan = RailsDev::ServicePorts.new(@services.except("debug"), @config)

    refute_includes plan.ports, "debug"
    assert_includes plan.override, '"debug": !reset null'
  end

  def test_connection_environment_is_empty_without_explicit_mappings
    plan = RailsDev::ServicePorts.new(@services, @config)

    assert_empty plan.environment({})
  end

  def test_maps_a_url_without_guessing_credentials_or_database
    @config.connect("redis", port: 6379, env: { "REDIS_URL" => "redis://user:password@%{host}:%{port}/2" })
    plan = RailsDev::ServicePorts.new(@services, @config)
    env = plan.environment({ ["redis", 6379, "tcp"] => { host: "127.0.0.1", port: "49123" } })

    assert_equal "redis://user:password@127.0.0.1:49123/2", env.fetch("REDIS_URL")
  end

  def test_rejects_a_mapping_to_an_unpublished_port
    @config.connect("internal", port: 8080, env: { "INTERNAL_PORT" => "%{port}" })

    assert_raises(RailsDev::Error) { RailsDev::ServicePorts.new(@services, @config) }
  end

  def test_distinguishes_multiple_services
    @config.connect("redis", port: 6379, env: { "CACHE_PORT" => "%{port}" })
    @config.connect("postgres", port: 5432, env: { "DB_PORT" => "%{port}" })
    plan = RailsDev::ServicePorts.new(@services, @config)
    endpoints = { ["redis", 6379, "tcp"] => { host: "127.0.0.1", port: "49123" },
                  ["postgres", 5432, "tcp"] => { host: "127.0.0.1", port: "49124" } }

    assert_equal({ "CACHE_PORT" => "49123", "DB_PORT" => "49124" }, plan.environment(endpoints))
  end

  def test_preserves_url_encoded_credentials
    @config.connect("redis", port: 6379, env: { "REDIS_URL" => "redis://user:p%40ss@%{host}:%{port}/2" })
    plan = RailsDev::ServicePorts.new(@services, @config)
    env = plan.environment({ ["redis", 6379, "tcp"] => { host: "127.0.0.1", port: "49123" } })

    assert_equal "redis://user:p%40ss@127.0.0.1:49123/2", env.fetch("REDIS_URL")
  end

  def test_app_mapping_replaces_an_inherited_mapping_for_the_same_variable
    @config.connect("redis", port: 6379, env: { "PORT" => "%{port}" })
    @config.connect("postgres", port: 5432, env: { "PORT" => "%{port}" })
    plan = RailsDev::ServicePorts.new(@services, @config)
    env = plan.environment({ ["postgres", 5432, "tcp"] => { host: "127.0.0.1", port: "49124" } })

    assert_equal({ "PORT" => "49124" }, env)
  end
end
