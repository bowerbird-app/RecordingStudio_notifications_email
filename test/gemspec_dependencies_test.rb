# frozen_string_literal: true

require "minitest/autorun"
require "rubygems"

class GemspecDependenciesTest < Minitest::Test
  def test_runtime_floors_exclude_core_7_and_notifications_before_0_14_7
    spec = Gem::Specification.load(File.expand_path("../recording_studio_notifications_email.gemspec", __dir__))
    studio = requirement_for(spec, "recording_studio")
    notifications = requirement_for(spec, "recording_studio_notifications")

    assert studio.satisfied_by?(Gem::Version.new("6.1.0"))
    assert studio.satisfied_by?(Gem::Version.new("6.3.0"))
    refute studio.satisfied_by?(Gem::Version.new("7.0.0"))

    assert notifications.satisfied_by?(Gem::Version.new("0.14.7"))
    assert notifications.satisfied_by?(Gem::Version.new("0.14.8"))
    refute notifications.satisfied_by?(Gem::Version.new("0.14.6"))
    refute notifications.satisfied_by?(Gem::Version.new("0.14.1"))
    refute notifications.satisfied_by?(Gem::Version.new("1.0.0"))
  end

  private

  def requirement_for(spec, name)
    dependency = spec.dependencies.find { |candidate| candidate.name == name }
    assert dependency, "expected a #{name} dependency"
    dependency.requirement
  end
end
