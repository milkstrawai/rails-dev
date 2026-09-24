# frozen_string_literal: true

require "test_helper"

class CLIArgumentsTest < Minitest::Test
  def setup
    super
    @output = StringIO.new
    @error = StringIO.new
  end

  def test_help_does_not_load_an_application
    assert_equal 0, run_cli("--root", "/missing/rails-dev-app", "--help")
    assert_includes @output.string, "services COMMAND"
    assert_empty @error.string
  end

  def test_start_help_describes_procfile_launching
    assert_equal 0, run_cli("start", "--help")
    refute_includes @output.string, "--skip-prepare"
    assert_empty @error.string
  end

  def test_start_help_describes_with_without_loading_an_app
    assert_equal 0, run_cli("start", "--root", "/missing/rails-dev-app", "--help")
    assert_includes @output.string, "--with"
    assert_empty @error.string
  end

  def test_services_help_lists_the_service_commands
    assert_equal 0, run_cli("services", "--help")
    assert_match(/services exec.*COMMAND/, @output.string)
    assert_includes @output.string, "services stop"
  end

  def test_start_help_describes_tailscale_without_loading_an_app
    assert_equal 0, run_cli("start", "--root", "/missing/rails-dev-app", "--help")
    assert_includes @output.string, "--tailscale"
    assert_empty @error.string
  end

  def test_service_commands_reject_tailscale
    assert_equal 1, run_cli("services", "start", "--tailscale")
    assert_includes @error.string, "--tailscale"
    assert_empty @output.string
  end

  def test_exec_help_keeps_the_full_command_name
    assert_equal 0, run_cli("services", "exec", "-h")
    assert_includes @output.string, "services exec -- COMMAND [ARGS]"
    refute_includes @output.string, "--skip-prepare"
  end

  def test_help_command_reaches_nested_commands
    assert_equal 0, run_cli("services", "help", "exec")
    assert_includes @output.string, "services exec -- COMMAND [ARGS]"
  end

  def test_version_does_not_load_an_application
    assert_equal 0, run_cli("--root", "/missing/rails-dev-app", "--version")
    assert_equal "#{RailsDev::VERSION}\n", @output.string
    assert_empty @error.string
  end

  def test_version_shortcut_works_on_service_commands
    assert_equal 0, run_cli("services", "exec", "-v")
    assert_equal "#{RailsDev::VERSION}\n", @output.string
    assert_empty @error.string
  end

  def test_missing_command_fails
    assert_equal 1, run_cli
    assert_includes @error.string, "rails-dev --help"
  end

  def test_missing_service_command_fails
    assert_equal 1, run_cli("services")
    assert_includes @error.string, "rails-dev services --help"
  end

  def test_unknown_command_fails
    assert_equal 1, run_cli("unknown")
    assert_includes @error.string, "unknown"
    assert_empty @output.string
  end

  def test_unknown_service_command_fails
    assert_equal 1, run_cli("services", "unknown")
    assert_includes @error.string, "unknown"
    assert_empty @output.string
  end

  def test_unknown_start_option_fails
    assert_equal 1, run_cli("start", "--unknown")
    assert_includes @error.string, "--unknown"
    assert_empty @output.string
  end

  def test_service_commands_reject_skip_prepare
    assert_equal 1, run_cli("services", "start", "--skip-prepare")
    assert_includes @error.string, "--skip-prepare"
    assert_empty @output.string
  end

  def test_service_commands_reject_with
    assert_equal 1, run_cli("services", "start", "--with", "worker")
    assert_includes @error.string, "--with"
    assert_empty @output.string
  end

  def test_exec_rejects_unknown_options_before_the_separator
    assert_equal 1, run_cli("services", "exec", "--unknown", "--", "ruby", "-v")
    assert_includes @error.string, "--unknown"
    assert_empty @output.string
  end

  def test_exec_requires_a_command
    assert_equal 1, run_cli("services", "exec", "--")
    assert_includes @error.string, "services exec -- COMMAND [ARGS]"
    assert_empty @output.string
  end

  def test_root_requires_a_value
    assert_equal 1, run_cli("start", "--root")
    assert_includes @error.string, "--root"
    assert_empty @output.string
  end

  def test_root_cannot_consume_the_exec_command_after_the_separator
    assert_equal 1, run_cli("services", "exec", "--root", "--", "ruby", "-v")
    assert_includes @error.string, "No value provided for option '--root'"
    assert_empty @output.string
  end

  def test_with_requires_a_value_before_loading_an_app
    assert_equal 1, run_cli("start", "--root", "/missing/rails-dev-app", "--with")
    assert_includes @error.string, "No value provided for option '--with'"
    assert_empty @output.string
  end

  def test_with_cannot_consume_another_option_as_its_name
    assert_equal 1, run_cli("start", "--root", "/missing/rails-dev-app", "--with", "--skip-prepare")
    assert_includes @error.string, "No value provided for option '--with'"
    assert_empty @output.string
  end

  private

  def run_cli(*arguments)
    RailsDev::CLI.run(arguments, output: @output, error: @error)
  end
end
