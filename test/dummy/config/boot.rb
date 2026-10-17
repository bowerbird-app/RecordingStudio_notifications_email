ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# rails test boots the application before test_helper. Start coverage here so
# the engine is measured. Direct ruby test runs start it from test_helper.
require_relative "../test/simplecov_start" if ARGV.include?("test")
# require "bootsnap/setup" # Speed up boot time by caching expensive operations.
