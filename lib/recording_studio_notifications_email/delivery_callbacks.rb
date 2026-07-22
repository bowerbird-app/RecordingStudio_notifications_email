# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module DeliveryCallbacks
    EVENT_METHOD_CONTRACT = {
      delivered: {
        predicate: :delivered?,
        predicate_aliases: [],
        mutator: :mark_delivered!,
        mutator_aliases: []
      },
      opened: {
        predicate: :email_opened?,
        predicate_aliases: %i[opened? read?],
        mutator: :mark_email_opened!,
        mutator_aliases: %i[mark_opened! mark_read!]
      },
      clicked: {
        predicate: :email_clicked?,
        predicate_aliases: %i[clicked?],
        mutator: :mark_email_clicked!,
        mutator_aliases: %i[mark_clicked!]
      },
      bounced: {
        predicate: :email_bounced?,
        predicate_aliases: %i[bounced? failed?],
        mutator: :mark_email_bounced!,
        mutator_aliases: %i[mark_bounced! mark_failed!]
      },
      complained: {
        predicate: :email_complained?,
        predicate_aliases: %i[complained? spam_reported?],
        mutator: :mark_email_complained!,
        mutator_aliases: %i[mark_complained! mark_spam_reported!]
      },
      unsubscribed: {
        predicate: :email_unsubscribed?,
        predicate_aliases: %i[unsubscribed? opted_out?],
        mutator: :mark_email_unsubscribed!,
        mutator_aliases: %i[mark_unsubscribed! mark_opted_out!]
      }
    }.freeze

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
      def mark_delivered!(reference:, delivered_at: Time.current,
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

      def mark_opened!(reference:, opened_at: Time.current,
                       configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :opened,
          reference: reference,
          occurred_at: opened_at,
          configuration: configuration
        )
      end

      def mark_clicked!(reference:, clicked_at: Time.current,
                        configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :clicked,
          reference: reference,
          occurred_at: clicked_at,
          configuration: configuration
        )
      end

      def mark_bounced!(reference:, bounced_at: Time.current,
                        configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :bounced,
          reference: reference,
          occurred_at: bounced_at,
          configuration: configuration
        )
      end

      def mark_complained!(reference:, complained_at: Time.current,
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

      def process_webhook_event!(event:, configuration: RecordingStudioNotificationsEmail.configuration)
        webhook_event = normalize_webhook_event(event)
        webhook_event = apply_webhook_event_transformer(webhook_event, configuration: configuration)

        mark_event_from_reference!(
          event_type: webhook_event.event_type,
          reference: webhook_event.reference,
          occurred_at: webhook_event.occurred_at,
          configuration: configuration
        )
      end

      private

      def resolve_reference!(reference, configuration:)
        return reference if reference.is_a?(DeliveryToken::Reference)

        DeliveryToken.verify!(reference, configuration: configuration)
      end

      def normalize_webhook_event(event)
        event.is_a?(WebhookEvent) ? event : WebhookEvent.new(**event)
      end

      def apply_webhook_event_transformer(webhook_event, configuration:)
        transformer = configuration.respond_to?(:webhook_event_transformer) ? configuration.webhook_event_transformer : nil
        return webhook_event unless transformer

        unless transformer.respond_to?(:call)
          raise InvalidWebhookTransformError, "webhook_event_transformer must respond to call"
        end

        transformed = transformer.call(webhook_event)
        return normalize_webhook_event(transformed) if transformed

        raise InvalidWebhookTransformError, "webhook_event_transformer returned nil"
      rescue ArgumentError, TypeError => error
        raise InvalidWebhookTransformError, "webhook_event_transformer returned invalid payload: #{error.message}"
      end

      def apply_event!(delivery, event_type:, occurred_at:)
        normalized_event = event_type.to_sym
        return apply_delivered!(delivery, occurred_at: occurred_at) if normalized_event == :delivered

        predicate = predicate_for(normalized_event).find { |name| delivery.respond_to?(name) }
        if predicate && delivery.public_send(predicate)
          mark_notification_as_read!(delivery, occurred_at: occurred_at) if normalized_event == :opened
          return :already_applied
        end

        mutator = mutator_for(normalized_event).find { |name| delivery.respond_to?(name) }
        unless mutator
          if normalized_event == :opened
            read_result = mark_notification_as_read!(delivery, occurred_at: occurred_at)
            return read_result if read_result
          end

          raise UnsupportedWebhookEventError, unsupported_event_message(normalized_event)
        end

        delivery.public_send(mutator, at: occurred_at)
        mark_notification_as_read!(delivery, occurred_at: occurred_at) if normalized_event == :opened
        :updated
      end

      def apply_delivered!(delivery, occurred_at:)
        return :already_applied if delivery.respond_to?(:delivered?) && delivery.delivered?

        raise UnsupportedWebhookEventError, unsupported_event_message(:delivered) unless delivery.respond_to?(:mark_delivered!)

        delivery.mark_delivered!(at: occurred_at)
        :updated
      end

      def predicate_for(event_type)
        callback_methods_for(event_type, type: :predicate)
      end

      def mutator_for(event_type)
        callback_methods_for(event_type, type: :mutator)
      end

      def callback_methods_for(event_type, type:)
        contract = EVENT_METHOD_CONTRACT[event_type.to_sym]
        return [] unless contract

        primary_key = type == :predicate ? :predicate : :mutator
        alias_key = type == :predicate ? :predicate_aliases : :mutator_aliases

        [contract.fetch(primary_key), *Array(contract.fetch(alias_key))].freeze
      end

      def unsupported_event_message(event_type)
        "delivery model does not support #{event_type} callbacks"
      end

      def mark_notification_as_read!(delivery, occurred_at:)
        notification = notification_for_delivery(delivery)
        return unless notification
        return unless notification.respond_to?(:read_at) && notification.respond_to?(:read_at=)

        return :already_applied unless notification.read_at.nil?

        notification.read_at = occurred_at
        notification.save! if notification.respond_to?(:save!)
        :updated
      end

      def notification_for_delivery(delivery)
        return delivery.notification if delivery.respond_to?(:notification)

        notification_id = delivery.respond_to?(:notification_id) ? delivery.notification_id : nil
        return unless notification_id
        return unless defined?(RecordingStudioNotifications::Notification)

        RecordingStudioNotifications::Notification.find_by(id: notification_id)
      end
    end
  end
end