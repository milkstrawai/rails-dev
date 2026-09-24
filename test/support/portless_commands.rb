# frozen_string_literal: true

class PortlessCommands < RailsDev::Commands
  attr_reader :calls
  attr_accessor :node_version

  def initialize(root)
    super(root, output: StringIO.new)
    @calls = []
    @node_version = "v24.19.0\n"
  end

  def capture(*argv)
    @calls << [:capture, *argv]
    node_version
  end

  def run(*argv)
    @calls << [:run, *argv]
  end

  def replace(argv)
    @calls << [:replace, *argv]
  end
end
