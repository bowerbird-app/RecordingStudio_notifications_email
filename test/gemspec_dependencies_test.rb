# frozen_string_literal: true

require "minitest/autorun"
require "rubygems"

class GemspecDependenciesTest < Minitest::Test
  def test_runtime_floors_require_core_7_1_and_notifications_0_20
    spec = Gem::Specification.load(File.expand_path("../recording_studio_notifications_email.gemspec", __dir__))
    studio = requirement_for(spec, "recording_studio")
    notifications = requirement_for(spec, "recording_studio_notifications")

    refute studio.satisfied_by?(Gem::Version.new("7.0.0"))
    assert studio.satisfied_by?(Gem::Version.new("7.1.0"))
    refute studio.satisfied_by?(Gem::Version.new("6.7.0"))
    refute studio.satisfied_by?(Gem::Version.new("6.1.0"))
    refute studio.satisfied_by?(Gem::Version.new("8.0.0"))

    assert notifications.satisfied_by?(Gem::Version.new("0.20.0"))
    assert notifications.satisfied_by?(Gem::Version.new("0.20.1"))
    refute notifications.satisfied_by?(Gem::Version.new("0.19.1"))
    refute notifications.satisfied_by?(Gem::Version.new("0.18.0"))
    refute notifications.satisfied_by?(Gem::Version.new("0.17.0"))
    refute notifications.satisfied_by?(Gem::Version.new("1.0.0"))
  end

  private

  def requirement_for(spec, name)
    dependency = spec.dependencies.find { |candidate| candidate.name == name }
    assert dependency, "expected a #{name} dependency"
    dependency.requirement
  end
end
