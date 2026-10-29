# frozen_string_literal: true

require "test_helper"

class PublicApiTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioNotificationsEmail.instance_variable_get(:@configuration)
    @original_adapter = RecordingStudioNotificationsEmail.instance_variable_get(:@adapter)
    RecordingStudioNotificationsEmail.reset_configuration!
  end

  def teardown
    RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, @original_configuration)
    RecordingStudioNotificationsEmail.instance_variable_set(:@adapter, @original_adapter)
  end

  def test_configure_supports_defaults_and_overrides
    returned = RecordingStudioNotificationsEmail.configure do |config|
      config.from = "notifications@example.test"
    end

    assert_same RecordingStudioNotificationsEmail.configuration, returned
    assert_equal "notifications@example.test", returned.from
    assert_same returned, RecordingStudioNotificationsEmail.config
  end

  def test_register_delegates_email_adapter_to_parent_registry
    registration = nil
    implementation = lambda do |channel, adapter|
      registration = [channel, adapter]
      adapter
    end

    RecordingStudioNotifications.stub(:register_channel, implementation) do
      result = RecordingStudioNotificationsEmail.register!

      assert_equal :email, registration.first
      assert_instance_of RecordingStudioNotificationsEmail::ActionMailerAdapter, registration.last
      assert_same registration.last, result
    end
  end

  def test_version_and_engine_are_public
    assert_equal "0.4.0", RecordingStudioNotificationsEmail::VERSION
    assert_kind_of Class, RecordingStudioNotificationsEmail::Engine
  end

  def test_gemspec_requires_recording_studio_6_1
    gemspec = File.read(File.expand_path("../recording_studio_notifications_email.gemspec", __dir__))

    assert_includes gemspec, 'spec.add_dependency "recording_studio", ">= 6.1.0"'
    refute_includes gemspec, "~> 4.2"
    refute_includes gemspec, ">= 6.3.0"
  end

  def test_development_pins_recording_studio_6_3
    gemfile = File.read(File.expand_path("../Gemfile", __dir__))
    dummy_gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v6.3.0"'
    assert_includes dummy_gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v6.3.0"'
    assert_includes dummy_gemfile, 'github: "bowerbird-app/RecordingStudio_commentable", tag: "v0.7.0"'
    assert_includes dummy_gemfile, 'github: "bowerbird-app/RecordingStudio_notifications"'
    assert_includes dummy_gemfile, 'tag: "v0.14.1"'
    refute_includes gemfile, 'tag: "v4.7.0"'
    refute_includes dummy_gemfile, 'tag: "v4.7.0"'
  end

  def test_engine_registers_channel_from_rails_prepare_callback
    prepare_callbacks = []
    config = Object.new
    config.define_singleton_method(:to_prepare) { |&block| prepare_callbacks << block }
    initializer = RecordingStudioNotificationsEmail::Engine.initializers.find do |candidate|
      candidate.name == "recording_studio_notifications_email.register_channel"
    end

    RecordingStudioNotificationsEmail::Engine.stub(:config, config) { initializer.block.call }

    called = false
    RecordingStudioNotificationsEmail.stub(:register!, -> { called = true }) { prepare_callbacks.fetch(0).call }

    assert called
  end
end
