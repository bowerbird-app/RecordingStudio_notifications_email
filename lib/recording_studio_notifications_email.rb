# frozen_string_literal: true

require "monitor"
require "openssl"
require "uri"
require "rails"
require "action_mailer/railtie"
require "recording_studio_notifications"
require "recording_studio_notifications_email/version"
require "recording_studio_notifications_email/configuration"
require "recording_studio_notifications_email/event"
require "recording_studio_notifications_email/correlation"
require "recording_studio_notifications_email/delivery_callbacks"
require "recording_studio_notifications_email/action_mailer_adapter"
require "recording_studio_notifications_email/engine"

module RecordingStudioNotificationsEmail
  class ConfigurationError < StandardError; end

  class << self
    def configuration
      configuration_mutex.synchronize { @configuration ||= Configuration.new }
    end
    alias config configuration

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def adapter
      configuration_mutex.synchronize do
        @adapter ||= ActionMailerAdapter.new(configuration: configuration)
      end
    end

    def register!
      unless defined?(RecordingStudioNotifications) &&
             RecordingStudioNotifications.respond_to?(:register_channel)
        raise ConfigurationError, "recording_studio_notifications must expose register_channel"
      end

      RecordingStudioNotifications.register_channel(configuration.channel, adapter)
    end

    def reset_configuration!
      configuration_mutex.synchronize do
        @configuration = Configuration.new
        @adapter = nil
      end
    end

    def mark_delivered_from_reference!(reference:, delivered_at: Time.current)
      DeliveryCallbacks.mark_delivered_from_reference!(
        reference: reference,
        delivered_at: delivered_at,
        configuration: configuration
      )
    end

    private

    def configuration_mutex
      @configuration_mutex ||= Monitor.new
    end
  end
end
