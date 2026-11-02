# frozen_string_literal: true

require "minitest/autorun"

class SecurityWorkflowTest < Minitest::Test
  def test_root_ci_runs_brakeman_and_bundler_audit
    workflow = File.read(File.expand_path("../.github/workflows/ci.yml", __dir__))
    gemfile = File.read(File.expand_path("../Gemfile", __dir__))

    assert_includes workflow, "name: Security"
    assert_includes workflow, "bundle exec brakeman --no-pager --quiet"
    assert_includes workflow, "bundle exec bundler-audit check --update"
    assert_includes gemfile, 'gem "brakeman", require: false'
    assert_includes gemfile, 'gem "bundler-audit", require: false'
  end
end
