# frozen_string_literal: true

require_relative "registry"
require_relative "recipient_registry"

module RecordingStudioNotificationsEmail
  class Configuration
    DEFAULT_TEMPLATE = "recording_studio_notifications_email/notification_mailer/notification"
    DEFAULT_ROLLUP_TEMPLATE = "recording_studio_notifications_email/notification_mailer/rollup"

    attr_accessor :from, :reply_to, :mailer_class, :channel, :message_verifier,
                  :signed_reference_expires_in, :message_id_domain
    attr_reader :templates, :recipients

    def initialize
      @from = ENV.fetch("RECORDING_STUDIO_NOTIFICATIONS_EMAIL_FROM", nil)
      @reply_to = nil
      @mailer_class = "RecordingStudioNotificationsEmail::NotificationMailer"
      @channel = :email
      @message_verifier = nil
      @signed_reference_expires_in = 30.days
      @message_id_domain = nil
      @templates = Registry.new(label: "template")
      @recipients = RecipientRegistry.new
      templates.register(:default, DEFAULT_TEMPLATE)
      templates.register(:rollup, DEFAULT_ROLLUP_TEMPLATE)
    end

    def template_for(notification_type)
      templates[notification_type] || templates.fetch(:default)
    end

    def rollup_template
      templates.fetch(:rollup)
    end

    def resolve_mailer_class
      return mailer_class if mailer_class.respond_to?(:with)

      mailer_class.to_s.constantize
    end

    def merge!(attributes)
      return self unless attributes.respond_to?(:each)

      attributes.each do |key, value|
        setter = "#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
      self
    end

    def to_h
      {
        channel: channel.to_sym,
        from: from,
        reply_to: reply_to,
        mailer_class: mailer_class.respond_to?(:name) ? mailer_class.name : mailer_class,
        signed_reference_expires_in: signed_reference_expires_in,
        message_id_domain: message_id_domain,
        templates: templates.keys,
        recipient_types: recipients.keys
      }
    end
  end
end
