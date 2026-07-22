# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module DeliveryCallbacks
    DeliveryUpdateResult = Data.define(
      :reference,
      :updated_delivery_ids,
      :already_delivered_ids,
      :missing_delivery_ids
    )

    WebhookUpdateResult = Data.define(
      :event_type,
      :reference,
      :updated_delivery_ids,
      :already_applied_delivery_ids,
      :missing_delivery_ids
    )

    class << self
      def mark_delivered_from_reference!(reference:, delivered_at: Time.current,
                                         configuration: RecordingStudioNotificationsEmail.configuration)
        resolved_reference = resolve_reference!(reference, configuration: configuration)
        requested_ids = resolved_reference.delivery_ids.map(&:to_s).uniq
        deliveries = RecordingStudioNotifications::Delivery.where(id: requested_ids).to_a

        found_by_id = deliveries.index_by { |delivery| delivery.id.to_s }
        missing_delivery_ids = requested_ids - found_by_id.keys
        updated_delivery_ids = []
        already_delivered_ids = []

        found_by_id.each_value do |delivery|
          if delivery.delivered?
            already_delivered_ids << delivery.id.to_s
          else
            delivery.mark_delivered!(at: delivered_at)
            updated_delivery_ids << delivery.id.to_s
          end
        end

        DeliveryUpdateResult.new(
          reference: resolved_reference,
          updated_delivery_ids: updated_delivery_ids.freeze,
          already_delivered_ids: already_delivered_ids.freeze,
          missing_delivery_ids: missing_delivery_ids.freeze
        )
      end

      def mark_opened_from_reference!(reference:, opened_at: Time.current,
                                      configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :opened,
          reference: reference,
          occurred_at: opened_at,
          configuration: configuration
        )
      end

      def mark_clicked_from_reference!(reference:, clicked_at: Time.current,
                                       configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :clicked,
          reference: reference,
          occurred_at: clicked_at,
          configuration: configuration
        )
      end

      def mark_bounced_from_reference!(reference:, bounced_at: Time.current,
                                       configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :bounced,
          reference: reference,
          occurred_at: bounced_at,
          configuration: configuration
        )
      end

      def mark_complained_from_reference!(reference:, complained_at: Time.current,
                                          configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :complained,
          reference: reference,
          occurred_at: complained_at,
          configuration: configuration
        )
      end

      def mark_unsubscribed_from_reference!(reference:, unsubscribed_at: Time.current,
                                            configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :unsubscribed,
          reference: reference,
          occurred_at: unsubscribed_at,
          configuration: configuration
        )
      end

      def mark_event_from_reference!(event_type:, reference:, occurred_at: Time.current,
                                     configuration: RecordingStudioNotificationsEmail.configuration)
        resolved_reference = resolve_reference!(reference, configuration: configuration)
        requested_ids = resolved_reference.delivery_ids.map(&:to_s).uniq
        deliveries = RecordingStudioNotifications::Delivery.where(id: requested_ids).to_a

        found_by_id = deliveries.index_by { |delivery| delivery.id.to_s }
        missing_delivery_ids = requested_ids - found_by_id.keys
        updated_delivery_ids = []
        already_applied_delivery_ids = []

        found_by_id.each_value do |delivery|
          case apply_event!(delivery, event_type: event_type, occurred_at: occurred_at)
          when :updated
            updated_delivery_ids << delivery.id.to_s
          when :already_applied
            already_applied_delivery_ids << delivery.id.to_s
          end
        end

        WebhookUpdateResult.new(
          event_type: event_type.to_sym,
          reference: resolved_reference,
          updated_delivery_ids: updated_delivery_ids.freeze,
          already_applied_delivery_ids: already_applied_delivery_ids.freeze,
          missing_delivery_ids: missing_delivery_ids.freeze
        )
      end

      def ingest_webhook_event!(event:, configuration: RecordingStudioNotificationsEmail.configuration)
        webhook_event = event.is_a?(WebhookEvent) ? event : WebhookEvent.new(**event)

        mark_event_from_reference!(
          event_type: webhook_event.event_type,
          reference: webhook_event.reference,
          occurred_at: webhook_event.occurred_at,
          configuration: configuration
        )
      end

      private

      def resolve_reference!(reference, configuration:)
        return reference if reference.is_a?(Correlation::Reference)

        Correlation.verify!(reference, configuration: configuration)
      end

      def apply_event!(delivery, event_type:, occurred_at:)
        normalized_event = event_type.to_sym
        return apply_delivered!(delivery, occurred_at: occurred_at) if normalized_event == :delivered

        predicate = predicate_for(normalized_event).find { |name| delivery.respond_to?(name) }
        return :already_applied if predicate && delivery.public_send(predicate)

        mutator = mutator_for(normalized_event).find { |name| delivery.respond_to?(name) }
        raise UnsupportedWebhookEventError, unsupported_event_message(normalized_event) unless mutator

        delivery.public_send(mutator, at: occurred_at)
        :updated
      end

      def apply_delivered!(delivery, occurred_at:)
        return :already_applied if delivery.respond_to?(:delivered?) && delivery.delivered?

        raise UnsupportedWebhookEventError, unsupported_event_message(:delivered) unless delivery.respond_to?(:mark_delivered!)

        delivery.mark_delivered!(at: occurred_at)
        :updated
      end

      def predicate_for(event_type)
        case event_type
        when :opened then %i[opened? email_opened? read?]
        when :clicked then %i[clicked? email_clicked?]
        when :bounced then %i[bounced? failed?]
        when :complained then %i[complained? spam_reported?]
        when :unsubscribed then %i[unsubscribed? opted_out?]
        else []
        end
      end

      def mutator_for(event_type)
        case event_type
        when :opened then %i[mark_opened! mark_email_opened! mark_read!]
        when :clicked then %i[mark_clicked! mark_email_clicked!]
        when :bounced then %i[mark_bounced! mark_failed!]
        when :complained then %i[mark_complained! mark_spam_reported!]
        when :unsubscribed then %i[mark_unsubscribed! mark_opted_out!]
        else []
        end
      end

      def unsupported_event_message(event_type)
        "delivery model does not support #{event_type} callbacks"
      end
    end
  end
end