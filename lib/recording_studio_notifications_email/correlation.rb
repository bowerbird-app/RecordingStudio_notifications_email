# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module Correlation
    PURPOSE = "recording_studio_notifications_email.correlation"
    HEADER = "X-Recording-Studio-Notification-Reference"
    DOMAIN_PATTERN = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*
                     [a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/ix

    Reference = Data.define(:notification_ids, :delivery_ids, :rollup_key) do
      def notification_id
        notification_ids.first
      end

      def delivery_id
        delivery_ids.first
      end

      def rollup?
        rollup_key.present? || delivery_ids.many?
      end
    end

    class << self
      def sign(notification: nil, notifications: nil, delivery: nil, deliveries: nil, rollup_key: nil,
               configuration: RecordingStudioNotificationsEmail.configuration)
        notification_ids = extract_records(
          singular: notification,
          plural: notifications,
          singular_label: "notification",
          plural_label: "notifications"
        )
        delivery_ids = extract_records(
          singular: delivery,
          plural: deliveries,
          singular_label: "delivery",
          plural_label: "deliveries"
        )
        validate_aligned_ids!(notification_ids, delivery_ids)
        expires_in = validated_expiry(configuration.signed_reference_expires_in)

        verifier(configuration).generate(
          {
            "notification_ids" => notification_ids.map(&:to_s),
            "delivery_ids" => delivery_ids.map(&:to_s),
            "rollup_key" => rollup_key.to_s.presence
          },
          purpose: PURPOSE,
          expires_in: expires_in
        )
      end

      def verify(token, configuration: RecordingStudioNotificationsEmail.configuration)
        payload = verifier(configuration).verified(token.to_s, purpose: PURPOSE)
        build_reference(payload)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end

      def verify!(token, configuration: RecordingStudioNotificationsEmail.configuration)
        payload = verifier(configuration).verify(token.to_s, purpose: PURPOSE)
        build_reference(payload) || raise(ActiveSupport::MessageVerifier::InvalidSignature)
      end

      def message_id(reference, configuration: RecordingStudioNotificationsEmail.configuration)
        domain = configuration.message_id_domain.to_s.strip
        return if domain.empty?
        unless domain.match?(DOMAIN_PATTERN)
          raise RecordingStudioNotificationsEmail::ConfigurationError, "message_id_domain is invalid"
        end

        verified_reference = verify!(reference, configuration: configuration)
        identity = JSON.generate(
          {
            "notification_ids" => verified_reference.notification_ids,
            "delivery_ids" => verified_reference.delivery_ids,
            "rollup_key" => verified_reference.rollup_key
          }
        )
        digest = OpenSSL::Digest::SHA256.hexdigest(identity)
        "<rsne-#{digest}@#{domain}>"
      end

      private

      def verifier(configuration)
        configured = configuration.message_verifier
        return configured if configured
        return Rails.application.message_verifier(PURPOSE) if Rails.application

        raise RecordingStudioNotificationsEmail::ConfigurationError,
              "configure message_verifier when no Rails application is available"
      end

      def validated_expiry(value)
        valid_type = value.is_a?(Numeric) ||
                     (defined?(ActiveSupport::Duration) && value.is_a?(ActiveSupport::Duration))
        return value if valid_type && value.to_f.positive?

        raise RecordingStudioNotificationsEmail::ConfigurationError,
              "signed_reference_expires_in must be a positive duration"
      end

      def extract_records(singular:, plural:, singular_label:, plural_label:)
        if singular.present? && plural.present?
          raise ArgumentError, "provide either #{singular_label} or #{plural_label}"
        end

        records = singular.present? ? Array(singular) : Array(plural)
        raise ArgumentError, "at least one #{singular_label} is required" if records.empty?

        records.map { |record| extract_id(record, singular_label).to_s }
      end

      def extract_id(record, label)
        id = record.respond_to?(:id) ? record.id : record
        raise ArgumentError, "#{label} must have an id" if id.to_s.strip.empty?

        id
      end

      def validate_aligned_ids!(notification_ids, delivery_ids)
        return if notification_ids.size == delivery_ids.size

        raise ArgumentError, "notifications and deliveries must match"
      end

      def build_reference(payload)
        return unless payload.respond_to?(:fetch)

        notification_ids = extract_payload_ids(payload, plural: "notification_ids", singular: "notification_id")
        delivery_ids = extract_payload_ids(payload, plural: "delivery_ids", singular: "delivery_id")
        return if notification_ids.empty? || delivery_ids.empty?
        return unless notification_ids.size == delivery_ids.size

        Reference.new(
          notification_ids: notification_ids.freeze,
          delivery_ids: delivery_ids.freeze,
          rollup_key: payload["rollup_key"].to_s.presence
        )
      rescue KeyError, TypeError, NoMethodError
        nil
      end

      def extract_payload_ids(payload, plural:, singular:)
        if payload.key?(plural)
          Array(payload.fetch(plural))
        elsif payload.key?(singular)
          [payload.fetch(singular)]
        else
          []
        end.map(&:to_s).reject(&:empty?)
      end
    end
  end
end
