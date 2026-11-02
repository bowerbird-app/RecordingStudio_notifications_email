# frozen_string_literal: true

require "minitest/autorun"
require "rubygems"

class GemspecDependenciesTest < Minitest::Test
  def test_runtime_floors_exclude_core_7_and_notifications_before_0_14
    spec = Gem::Specification.load(File.expand_path("../recording_studio_notifications_email.gemspec", __dir__))
    studio = requirement_for(spec, "recording_studio")
    notifications = requirement_for(spec, "recording_studio_notifications")

    assert studio.satisfied_by?(Gem::Version.new("6.1.0"))
    assert studio.satisfied_by?(Gem::Version.new("6.3.0"))
    refute studio.satisfied_by?(Gem::Version.new("7.0.0"))

    assert notifications.satisfied_by?(Gem::Version.new("0.14.0"))
    assert notifications.satisfied_by?(Gem::Version.new("0.14.1"))
    refute notifications.satisfied_by?(Gem::Version.new("0.13.9"))
    refute notifications.satisfied_by?(Gem::Version.new("1.0.0"))
  end

  def test_repository_pins_and_view_component_stay_put
    root = File.expand_path("..", __dir__)
    gemfile = File.read(File.join(root, "Gemfile"))
    dummy_gemfile = File.read(File.join(root, "test/dummy/Gemfile"))
    root_lock = File.read(File.join(root, "Gemfile.lock"))
    dummy_lock = File.read(File.join(root, "test/dummy/Gemfile.lock"))

    assert_includes gemfile, 'tag: "v0.1.332"'
    assert_includes dummy_gemfile, 'tag: "v0.1.332"'
    assert_includes dummy_gemfile, 'tag: "v0.11.3"'
    assert_includes root_lock, "view_component (4.20.0)"
    assert_includes dummy_lock, "view_component (4.20.0)"
  end

  private

  def requirement_for(spec, name)
    dependency = spec.dependencies.find { |candidate| candidate.name == name }
    assert dependency, "expected a #{name} dependency"
    dependency.requirement
  end
end
