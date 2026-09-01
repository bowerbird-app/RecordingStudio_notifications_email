# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  # Read-only, normalized view of a parent notification. Presentation helpers
  # deliberately delegate to RecordingStudio's public addon API.
  class Event
    attr_reader :source, :delivery

    def self.wrap(source, delivery: nil)
      return source if source.is_a?(self) && delivery.nil?

      new(source, delivery: delivery)
    end

    def initialize(source, delivery: nil)
      raise ArgumentError, "notification is required" if source.nil?

      @source = source
      @delivery = delivery
    end

    def id
      attribute(:id)
    end

    def notification_type
      value = attribute(:notification_type_key) || attribute(:notification_type) || attribute(:action) || :generic
      normalized = value.to_s.strip
      normalized.empty? ? :generic : normalized.to_sym
    end

    def title
      value = presentation_attribute(:title)
      return sanitize_header_text(value) if value.present?

      fallback = [recordable_type_label, attribute(:action)].compact_blank.join(" ")
      sanitize_header_text(fallback).presence || "Notification"
    end

    def body
      presentation_attribute(:body).to_s.presence
    end

    def url
      value = presentation_attribute(:url).to_s.presence
      return unless value
      return if unsafe_url_characters?(value)

      if defined?(RecordingStudioNotifications::UrlSafety)
        return value if RecordingStudioNotifications::UrlSafety.safe?(value)
      elsif fallback_url_safe?(value)
        return value
      end

      nil
    rescue URI::InvalidURIError
      nil
    end

    def metadata
      value = attribute(:metadata)
      value.respond_to?(:to_h) ? deep_freeze(value.to_h.deep_dup) : {}.freeze
    end

    def recipient
      attribute(:recipient)
    end

    def actor
      attribute(:actor)
    end

    def notifiable
      attribute(:notifiable) || attribute(:recordable) || recording_recordable
    end

    def recording
      attribute(:recording)
    end

    def root_recording
      explicit = attribute(:root_recording)
      return explicit if explicit
      return unless recording

      recording_studio_call(:root_recording_or_self, recording)
    end

    def occurred_at
      attribute(:occurred_at) || attribute(:created_at)
    end

    def recordable_name
      recording_studio_call(:recordable_name, notifiable)
    end

    def recordable_type_label
      recording_studio_call(:recordable_type_label, notifiable)
    end

    def root_recording_id
      root = root_recording
      return unless root

      recording_studio_call(:root_recording_id_for, root) || root.try(:id)
    end

    private

    def presentation_attribute(name)
      return attribute(name) unless delivery

      payload = resolved_delivery_payload
      return attribute(name) unless payload.respond_to?(name)

      payload.public_send(name)
    end

    def resolved_delivery_payload
      return @resolved_delivery_payload if defined?(@resolved_delivery_payload)

      @resolved_delivery_payload =
        if delivery_payload_available?
          RecordingStudioNotifications.delivery_payload_for(notification: source, delivery: delivery)
        end
    end

    def delivery_payload_available?
      delivery &&
        defined?(RecordingStudioNotifications) &&
        RecordingStudioNotifications.respond_to?(:delivery_payload_for)
    end

    def attribute(name)
      return source.public_send(name) if source.respond_to?(name)
      return source[name] if source.respond_to?(:key?) && source.key?(name)

      string_name = name.to_s
      source[string_name] if source.respond_to?(:key?) && source.key?(string_name)
    end

    def recording_studio_call(method_name, value)
      return if value.nil?
      return unless defined?(RecordingStudio) && RecordingStudio.respond_to?(method_name)

      RecordingStudio.public_send(method_name, value)
    rescue ArgumentError, NameError
      nil
    end

    def sanitize_header_text(value)
      value.to_s.gsub(/[\r\n]+/, " ").strip
    end

    def fallback_url_safe?(value)
      return !value.start_with?("//") if value.start_with?("/")

      uri = URI.parse(value)
      [URI::HTTP, URI::HTTPS].any? { |type| uri.is_a?(type) } && uri.host.present?
    end

    def unsafe_url_characters?(value)
      value.match?(/[\\\x00-\x1F\x7F]/)
    end

    def recording_recordable
      current_recording = recording
      return unless current_recording.respond_to?(:recordable)

      current_recording.recordable
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each do |key, nested|
          deep_freeze(key)
          deep_freeze(nested)
        end
      when Array
        value.each { |nested| deep_freeze(nested) }
      end
      value.freeze
    end
  end
end
