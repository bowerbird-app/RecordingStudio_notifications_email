# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

begin
  require_relative "simplecov_start"
rescue LoadError
  warn "simplecov is not installed; dummy coverage will not be recorded"
end

require_relative "../config/environment"
require "rails/test_help"
