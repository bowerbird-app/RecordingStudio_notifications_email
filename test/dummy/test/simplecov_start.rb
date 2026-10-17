# frozen_string_literal: true

return if ENV["DISABLE_SIMPLECOV"] == "true"

require "coverage"
return if Coverage.running?

require "simplecov"

SimpleCov.start do
  command_name "dummy"
  root File.expand_path("../../..", __dir__)
  coverage_dir File.expand_path("../../../coverage", __dir__)
  enable_coverage :branch
  skip "/test/"
  skip "/config/"
  skip "/db/"
  skip "/vendor/"
end
