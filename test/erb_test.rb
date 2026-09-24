# frozen_string_literal: true

require "test_helper"
require "net/http"
require_relative "support/cli_process"

class ErbTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.remove_entry(@root)
    FileUtils.cp_r(fixture("erb"), @root)
    File.chmod(0o755, File.join(@root, "bin/rails"))
    @socket = TCPServer.new("127.0.0.1", 0)
    File.write(File.join(@root, "config/rails_dev.rb"), <<~RUBY)
      RailsDev.configure do |config|
        config.https = false
        config.http :web, port: #{@socket.addr[1]}
      end
    RUBY
  end

  def teardown
    super
  ensure
    @socket.close
  end

  def test_real_rails_instances_render_erb_with_independent_ports_and_cookies
    first, first_url = start_erb
    second, second_url = start_erb
    response = Net::HTTP.get_response(URI(second_url))

    assert_includes response.body, "<h1>ERB instance</h1>"
    assert_includes response["set-cookie"], "rails-dev-#{URI(second_url).port}-visit=erb"
    refute_equal first_url, second_url
    finish(first)

    assert_equal "200", Net::HTTP.get_response(URI(second_url)).code
    assert_equal 130, finish(second).exitstatus
  end

  private

  def start_erb
    pid = start_cli({ "RAILS_DEV_GEM_ROOT" => File.expand_path("..", __dir__) })
    wait_until(pid, timeout: 30) { output(pid).include?("Ready:") }
    [pid, output(pid).match(%r{Ready: (http://127\.0\.0\.1:\d+)})[1]]
  end
end
