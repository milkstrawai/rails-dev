# frozen_string_literal: true

require_relative "lib/rails_dev/version"

Gem::Specification.new do |spec|
  spec.name = "rails-dev"
  spec.version = RailsDev::VERSION
  spec.authors = ["Ali Hamdi Ali Fadel"]
  spec.email = ["aliosm1997@gmail.com"]
  spec.summary = "Available ports, HTTPS, and Tailscale for Rails development with Foreman."
  spec.homepage = "https://github.com/milkstrawai/rails-dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("{lib,exe,docs}/**/*").reject { |file| File.directory?(file) } +
               %w[CHANGELOG.md LICENSE.txt README.md]
  spec.bindir = "exe"
  spec.executables = ["rails-dev"]
  spec.require_paths = ["lib"]

  spec.add_dependency "bundler", ">= 2.5", "< 5"
  spec.add_dependency "foreman", "~> 0.90"
  spec.add_dependency "json", "~> 2.7"
  spec.add_dependency "thor", "~> 1.5"
end
