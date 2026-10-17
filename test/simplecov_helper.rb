# frozen_string_literal: true

return if ENV["DISABLE_SIMPLECOV"] == "true"

begin
  require "simplecov"
rescue LoadError
  return
end

SimpleCov.start do
  command_name "gem"
  enable_coverage :branch
  skip "/test/"
  skip "/config/"
  skip "/db/"
  skip "/vendor/"
end
