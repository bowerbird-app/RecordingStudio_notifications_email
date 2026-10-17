# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module Webhooks
    # Host-registered action for recording_studio_webhooks.
    #
    # The webhooks engine owns the route, signature check, and dedupe. This
    # class turns an accepted inbound event into a WebhookEvent. The host
    # provider must emit a canonical event type and put the correlation header
    # value on the payload as "reference".
    class ApplyEvent
      ACTION_NAME = "recording_studio_notifications_email.apply_event"

      class << self
        def call(context)
          RecordingStudioNotificationsEmail.process_webhook_event!(event: build_event(context))
        end

        def register!(provider:, name: ACTION_NAME, event: "*", **)
          unless defined?(RecordingStudioWebhooks) && RecordingStudioWebhooks.respond_to?(:register_action)
            raise ConfigurationError, "recording_studio_webhooks must be loaded before registering #{ACTION_NAME}"
          end

          RecordingStudioWebhooks.register_action(name, self, provider: provider, event: event, **)
        end

        def build_event(context)
          inbound = context.inbound_event
          payload = stringify_payload(context.payload)
          WebhookEvent.new(**webhook_attributes(inbound, payload))
        end

        private

        def webhook_attributes(inbound, payload)
          {
            provider: inbound.provider_name,
            event_type: inbound.event_type,
            reference: required_reference(payload),
            occurred_at: occurred_at_for(payload, inbound),
            external_event_id: external_event_id_for(inbound),
            external_message_id: payload["external_message_id"] || payload["message_id"],
            metadata: hash_metadata(payload["metadata"]),
            bounce_type: bounce_type_for(payload)
          }
        end

        def required_reference(payload)
          reference = payload["reference"].to_s.strip
          raise InvalidWebhookPayloadError, "reference is required" if reference.empty?

          reference
        end

        def external_event_id_for(inbound)
          return unless inbound.respond_to?(:provider_event_id)

          inbound.provider_event_id
        end

        def bounce_type_for(payload)
          direct = first_present_value(payload, "bounce_type", "bounceType")
          return direct if direct

          metadata = payload["metadata"]
          return unless metadata.is_a?(Hash)

          first_present_value(metadata, "bounce_type", "bounceType", :bounce_type)
        end

        def first_present_value(hash, *keys)
          keys.each do |key|
            value = hash[key]
            return value if present_value?(value)
          end

          nil
        end

        def present_value?(value)
          !value.nil? && !value.to_s.strip.empty?
        end

        def hash_metadata(value)
          value.is_a?(Hash) ? value : {}
        end

        def stringify_payload(payload)
          hash = payload.respond_to?(:to_h) ? payload.to_h : {}
          hash.each_with_object({}) do |(key, value), result|
            result[key.to_s] = value
          end
        end

        def occurred_at_for(payload, inbound)
          parsed = parse_time(payload["occurred_at"])
          return parsed if parsed
          return inbound.received_at if inbound.respond_to?(:received_at) && inbound.received_at

          Time.current
        end

        def parse_time(raw)
          return raw if raw.is_a?(Time)
          return nil if raw.nil? || (raw.is_a?(String) && raw.strip.empty?)
          return nil unless raw.respond_to?(:to_time)

          raw.to_time
        end
      end
    end
  end
end
