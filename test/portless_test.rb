# frozen_string_literal: true

require "test_helper"
require_relative "support/portless_commands"

class PortlessTest < Minitest::Test
  include TestWorkspace

  def setup
    super
    @commands = PortlessCommands.new(@root)
    @commands.env.merge!("XDG_DATA_HOME" => @workspace, "PORTLESS_STATE_DIR" => File.join(@workspace, "proxy"))
    @proxy = RailsDev::Portless.new(@commands)
    @prefix = File.join(@workspace, "rails-dev/portless", RailsDev::Portless::VERSION)
    @package = File.join(@prefix, "lib/node_modules/portless")
    @cli = ["node", File.join(@package, "dist/cli.js")]
  end

  def test_missing_installation_explains_machine_setup
    error = assert_raises(RailsDev::Error) { @proxy.check }

    assert_includes error.message, "rails-dev setup"
    assert_empty @commands.calls
  end

  def test_installs_the_pinned_version_without_running_package_scripts
    @proxy.install

    assert_equal [
      [:capture, "node", "--version"],
      [:run, "npm", "install", "--global", "--prefix", @prefix,
       "--ignore-scripts", "--no-audit", "--no-fund", "portless@#{RailsDev::Portless::VERSION}"]
    ], @commands.calls
  end

  def test_reuses_the_installed_pinned_version
    install_fixture
    @proxy.install

    assert_equal [[:capture, "node", "--version"]], @commands.calls
  end

  def test_replaces_a_different_installed_version
    install_fixture "older-portless-package.json"
    @proxy.install

    assert_equal :run, @commands.calls.last.first
    assert_equal "portless@#{RailsDev::Portless::VERSION}", @commands.calls.last.last
  end

  def test_rejects_an_unsupported_node_version_before_installation
    @commands.node_version = "v22.20.0\n"
    error = assert_raises(RailsDev::Error) { @proxy.install }

    assert_includes error.message, "Node.js 24 or newer"
    assert_equal [[:capture, "node", "--version"]], @commands.calls
  end

  def test_setup_forwards_the_port_and_local_proxy_settings
    install_fixture
    @commands.env.merge!("PORTLESS_LAN" => "1", "PORTLESS_WILDCARD" => "1")
    @proxy.setup(port: 8443)

    assert_equal [:replace, *@cli, "service", "install", "--https", "--port", "8443", "--tld", "localhost"],
                 @commands.calls.last
    assert_equal({ "PORTLESS_LAN" => "0", "PORTLESS_WILDCARD" => "0" },
                 @commands.env.slice("PORTLESS_LAN", "PORTLESS_WILDCARD"))
  end

  def test_doctor_forwards_to_portless_without_running_setup
    install_fixture
    @proxy.doctor

    assert_equal [[:replace, *@cli, "doctor"]], @commands.calls
  end

  def test_doctor_explains_a_missing_installation
    error = assert_raises(RailsDev::Error) { @proxy.doctor }

    assert_includes error.message, "rails-dev setup"
    assert_empty @commands.calls
  end

  private

  def install_fixture(name = "portless-package.json")
    FileUtils.mkdir_p(@package)
    FileUtils.cp(fixture(name), File.join(@package, "package.json"))
  end
end
