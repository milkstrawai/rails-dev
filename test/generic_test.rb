# frozen_string_literal: true

require "test_helper"
require_relative "support/cli_process"

class GenericTest < Minitest::Test
  include TestWorkspace
  include CLIProcess

  def setup
    super
    FileUtils.mkdir_p(File.join(@root, "config"))
    @socket = TCPServer.new("127.0.0.1", 0)
    File.write(File.join(@root, "Procfile.dev"), "web: bin/rails server\n")
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

  def test_runs_without_javascript_or_compose
    File.unlink(File.join(@root, "package.json"))
    pid = start_cli(arguments: ["start", "--root", @root])
    response = ready_response(pid)

    assert_operator response.fetch("rails_port").to_i, :>, @socket.addr[1]
    assert_nil response.fetch("vite_url")
    refute(events.any? { |event| event["event"] == "compose_up" })
    assert_equal 130, finish(pid).exitstatus
  end

  def test_foreman_keeps_its_normal_environment_file_loading
    File.write(File.join(@root, ".env"), "PGPORT=12345\n")
    pid = start_cli({ "PGPORT" => "23456" }, arguments: ["start", "--root", @root])

    assert_equal "12345", ready_response(pid).fetch("pgport")
    assert_equal "PGPORT=12345\n", File.read(File.join(@root, ".env"))
    finish(pid)
  end

  def test_asset_watchers_keep_their_input_open
    File.open(File.join(@root, "Procfile.dev"), "a") do |file|
      file.puts "css: ruby -e '$stdout.sync = true; puts \"Watching\"; STDIN.read; abort \"Watch input closed\"'"
    end
    pid = start_cli(arguments: ["start", "--root", @root])
    ready_response(pid)
    wait_until(pid) { output(pid).include?("Watching") }

    assert_equal 130, finish(pid).exitstatus
    refute_includes output(pid), "Watch input closed"
  end

  def test_primary_port_works_when_web_is_not_the_first_entry
    File.write(File.join(@root, "Procfile.dev"), "watch: ruby -e 'sleep'\nweb: bin/rails server -p $PORT\n")
    pid = start_cli(arguments: ["start", "--root", @root])

    assert_equal ready_response(pid).fetch("rails_port"), events.find { |event|
      event["role"] == "rails"
    }.fetch("port").to_s
    finish(pid)
  end

  def test_an_alternate_procfile_keeps_the_app_working_directory
    FileUtils.mv(File.join(@root, "Procfile.dev"), File.join(@root, "config/Procfile.dev"))
    File.write(File.join(@root, "config/rails_dev.local.rb"), <<~RUBY)
      RailsDev.configure { |config| config.procfile = "config/Procfile.dev" }
    RUBY
    pid = start_cli

    assert_equal "rails", ready_response(pid).fetch("role")
    finish(pid)
  end
end
