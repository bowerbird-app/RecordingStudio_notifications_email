# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib" << "test"
  task.test_files = FileList["test/**/*_test.rb"].exclude("test/dummy/**/*_test.rb")
end

namespace :test do
  desc "Run all gem tests"
  task all: :test
end

task default: :test
