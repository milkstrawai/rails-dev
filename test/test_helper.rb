# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rails_dev"
require "minitest/autorun"
require "fileutils"
require "socket"
require "stringio"
require "tmpdir"

module TestWorkspace
  def setup
    super
    @workspace = Dir.mktmpdir("rails-dev-test-")
    @root = File.join(@workspace, "app")
    FileUtils.cp_r(File.join(__dir__, "fixtures/app"), @root)
  end

  def teardown
    FileUtils.remove_entry(@workspace)
    super
  end

  def fixture(name)
    File.join(__dir__, "fixtures", name)
  end
end
