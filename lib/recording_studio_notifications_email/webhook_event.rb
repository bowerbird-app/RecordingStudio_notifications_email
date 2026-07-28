# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  class WebhookEvent
    EVENT_TYPES = %i[delivered opened clicked bounced complained unsubscribed].freeze

    attr_reader :provider, :event_type, :occurred_at, :external_event_id,
                :external_message_id, :reference, :metadata, :idempotency_key

    def initialize(provider:, event_type:, reference:, occurred_at: Time.current,
                   external_event_id: nil, external_message_id: nil, metadata: {},
                   idempotency_key: nil)
      @provider = normalize_provider(provider)
      @event_type = normalize_event_type(event_type)
      @reference = normalize_reference(reference)
      @occurred_at = normalize_occurred_at(occurred_at)
      @external_event_id = normalize_optional_string(external_event_id)
      @external_message_id = normalize_optional_string(external_message_id)
      @metadata = normalize_metadata(metadata)
      @idempotency_key = normalize_idempotency_key(idempotency_key)
    end

    def to_h
      {
        provider: provider,
        event_type: event_type,
        occurred_at: occurred_at,
        external_event_id: external_event_id,
        external_message_id: external_message_id,
        reference: reference,
        metadata: metadata,
        idempotency_key: idempotency_key
      }
    end

    private

    def normalize_provider(value)
      provider = value.to_s.strip.downcase
      raise InvalidWebhookPayloadError, "provider is required" if provider.empty?

      provider.to_sym
    end

    def normalize_event_type(value)
      event_type = value.to_s.strip.downcase
      raise InvalidWebhookPayloadError, "event_type is required" if event_type.empty?

      normalized = event_type.to_sym
      return normalized if EVENT_TYPES.include?(normalized)

      raise UnsupportedWebhookEventError, "unsupported event_type: #{event_type}"
    end

    def normalize_reference(value)
      reference = value.to_s.strip
      raise InvalidWebhookPayloadError, "reference is required" if reference.empty?

      reference
    end

    def normalize_occurred_at(value)
      return value if value.is_a?(Time)
      return value.to_time if value.respond_to?(:to_time)

      raise InvalidWebhookPayloadError, "occurred_at must be time-like"
    end

    def normalize_optional_string(value)
      return nil if value.nil?

      normalized = value.to_s.strip
      normalized.empty? ? nil : normalized
    end

    def normalize_metadata(value)
      raise InvalidWebhookPayloadError, "metadata must be a Hash" unless value.is_a?(Hash)

      value.deep_dup.freeze
    end

    def normalize_idempotency_key(value)
      unless value.nil?
        normalized = value.to_s.strip
        raise InvalidWebhookPayloadError, "idempotency_key cannot be blank" if normalized.empty?

        return normalized
      end

      return "#{provider}:#{external_event_id}" if external_event_id

      fingerprint = [
        provider,
        event_type,
        reference,
        external_message_id,
        occurred_at.utc.strftime("%Y-%m-%dT%H:%M:%S.%6NZ")
      ].join("|")
      digest = OpenSSL::Digest::SHA256.hexdigest(fingerprint)
      "#{provider}:synthetic:#{digest}"
    end
  end
end