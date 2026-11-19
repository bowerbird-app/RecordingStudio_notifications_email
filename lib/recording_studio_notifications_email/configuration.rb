# frozen_string_literal: true

require_relative "recipient_registry"

module RecordingStudioNotificationsEmail
  class Configuration
    DEFAULT_TEMPLATE = "recording_studio_notifications_email/notification_mailer/notification"
    DEFAULT_ROLLUP_TEMPLATE = "recording_studio_notifications_email/notification_mailer/rollup"

    attr_accessor :from, :reply_to, :mailer_class, :channel, :message_verifier,
                  :signed_reference_expires_in, :message_id_domain, :reply_domain,
                  :reply_address_expires_in, :require_inbound_authentication,
                  :reply_max_body_bytes, :reply_max_attachment_bytes, :reply_max_attachments
    attr_reader :recipients

    def initialize
      @from = ENV.fetch("RECORDING_STUDIO_NOTIFICATIONS_EMAIL_FROM", nil)
      @reply_to = nil
      @mailer_class = "RecordingStudioNotificationsEmail::NotificationMailer"
      @channel = :email
      @message_verifier = nil
      @signed_reference_expires_in = 30.days
      @message_id_domain = nil
      apply_reply_defaults
      @recipients = RecipientRegistry.new
    end

    def resolve_mailer_class
      return mailer_class.to_s.constantize if mailer_class.is_a?(String) || mailer_class.is_a?(Symbol)

      return mailer_class if mailer_class.respond_to?(:with)

      mailer_class.to_s.constantize
    end

    def inbound_authserv_ids
      Array(@inbound_authserv_ids).filter_map { |id| id.to_s.strip.downcase.presence }.uniq
    end

    def inbound_authserv_ids=(value)
      @inbound_authserv_ids = Array(value)
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
        recipient_types: recipients.keys
      }.merge(reply_settings)
    end

    private

    def reply_settings
      {
        reply_domain: reply_domain,
        reply_address_expires_in: reply_address_expires_in,
        require_inbound_authentication: require_inbound_authentication,
        inbound_authserv_ids: inbound_authserv_ids,
        reply_max_body_bytes: reply_max_body_bytes,
        reply_max_attachment_bytes: reply_max_attachment_bytes,
        reply_max_attachments: reply_max_attachments
      }
    end

    def apply_reply_defaults
      @reply_domain = nil
      @reply_address_expires_in = 30.days
      @require_inbound_authentication = true
      @inbound_authserv_ids = []
      @reply_max_body_bytes = 64 * 1024
      @reply_max_attachment_bytes = 10 * 1024 * 1024
      @reply_max_attachments = 10
    end
  end
end
