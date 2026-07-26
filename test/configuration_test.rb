# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  class FakeMailer
    def self.with(...)
      self
    end
  end

  def setup
    @configuration = RecordingStudioNotificationsEmail::Configuration.new
  end

  def test_defaults_include_email_channel_and_template_constants
    assert_equal :email, @configuration.channel
    assert_equal 30.days, @configuration.signed_reference_expires_in
    assert_nil @configuration.webhook_event_transformer
    assert_equal "recording_studio_notifications_email/notification_mailer/notification",
                 RecordingStudioNotificationsEmail::Configuration::DEFAULT_TEMPLATE
    assert_equal "recording_studio_notifications_email/notification_mailer/rollup",
                 RecordingStudioNotificationsEmail::Configuration::DEFAULT_ROLLUP_TEMPLATE
  end

  def test_merge_updates_known_values_without_a_template_registry
    @configuration.merge!("from" => "notifications@example.test", unknown: true)

    assert_equal "notifications@example.test", @configuration.from
    refute_respond_to @configuration, :unknown
    refute_respond_to @configuration, :templates
  end

  def test_merge_can_set_webhook_event_transformer
    transformer = ->(event) { event }

    @configuration.merge!(webhook_event_transformer: transformer)

    assert_equal transformer, @configuration.webhook_event_transformer
  end

  def test_resolve_mailer_class_constantizes_string_values
    @configuration.mailer_class = "ConfigurationTest::FakeMailer"

    assert_equal ConfigurationTest::FakeMailer, @configuration.resolve_mailer_class
  end
end
