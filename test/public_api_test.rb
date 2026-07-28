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
    end

    RecordingStudioNotifications.stub(:register_channel, implementation) do
      result = RecordingStudioNotificationsEmail.register!

      assert_equal :email, registration.first
      assert_instance_of RecordingStudioNotificationsEmail::ActionMailerAdapter, registration.last
      assert_same registration.last, result
    end
  end

  def test_version_and_engine_are_public
    refute_nil RecordingStudioNotificationsEmail::VERSION
    assert_kind_of Class, RecordingStudioNotificationsEmail::Engine
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
