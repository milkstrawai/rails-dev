# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

RuboCop::RakeTask.new do |task|
  task.options = ["--no-server"]
end

Rake::TestTask.new(:test_docker) do |task|
  task.libs << "test"
  task.pattern = "test/acceptance/test_*.rb"
end

Rake::TestTask.new(:test_https) do |task|
  task.libs << "test"
  task.pattern = "test/https/test_*.rb"
end

task default: %i[test rubocop]
