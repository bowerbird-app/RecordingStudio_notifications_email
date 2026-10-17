# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module DeliveryCallbacks
    EVENT_METHOD_CONTRACT = {
      delivered: {
        predicate: :delivered?,
        mutator: :mark_delivered!
      },
      opened: {
        predicate: :email_opened?,
        mutator: :mark_email_opened!
      },
      clicked: {
        predicate: :email_clicked?,
        mutator: :mark_email_clicked!
      },
      bounced: {
        predicate: :email_bounced?,
        mutator: :mark_email_bounced!
      },
      complained: {
        predicate: :email_complained?,
        mutator: :mark_email_complained!
      },
      unsubscribed: {
        predicate: :email_unsubscribed?,
        mutator: :mark_email_unsubscribed!
      }
    }.freeze

    SUPPRESSION_REASONS = {
      bounced: "bounce",
      complained: "complaint",
      unsubscribed: "unsubscribed"
    }.freeze

    # Notifications 0.10 stores these in delivery metadata and does not define
    # email_opened? and the other predicates. Use the predicate when a delivery
    # implements it, otherwise the timestamp the mutator writes.
    EMAIL_TIMESTAMP_KEYS = {
      opened: "email_opened_at",
      clicked: "email_clicked_at",
      bounced: "email_bounced_at",
      complained: "email_complained_at",
      unsubscribed: "email_unsubscribed_at"
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

        RecordingStudioNotifications::Delivery.transaction(requires_new: true) do
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

      def mark_bounced!(reference:, bounced_at: Time.current, provider: nil, bounce_type: nil,
                        configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :bounced,
          reference: reference,
          occurred_at: bounced_at,
          suppression: suppression_for(provider, bounce_type),
          configuration: configuration
        )
      end

      def mark_complained!(reference:, complained_at: Time.current, provider: nil,
                           configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :complained,
          reference: reference,
          occurred_at: complained_at,
          suppression: suppression_for(provider),
          configuration: configuration
        )
      end

      def mark_unsubscribed!(reference:, unsubscribed_at: Time.current, provider: nil,
                             configuration: RecordingStudioNotificationsEmail.configuration)
        mark_event_from_reference!(
          event_type: :unsubscribed,
          reference: reference,
          occurred_at: unsubscribed_at,
          suppression: suppression_for(provider),
          configuration: configuration
        )
      end

      def mark_event_from_reference!(event_type:, reference:, occurred_at: Time.current,
                                     suppression: nil,
                                     configuration: RecordingStudioNotificationsEmail.configuration)
        resolved_reference = resolve_reference!(reference, configuration: configuration)
        requested_ids = resolved_reference.delivery_ids.map(&:to_s).uniq
        deliveries = RecordingStudioNotifications::Delivery.where(id: requested_ids).to_a

        found_by_id = deliveries.index_by { |delivery| delivery.id.to_s }
        missing_delivery_ids = requested_ids - found_by_id.keys
        normalized_event = event_type.to_sym

        # Commit suppressions before the delivery transaction. A later raise
        # from mark_email_*! must leave the address suppressed. Soft bounces
        # still update the delivery and do not write a row.
        provider, bounce_type = suppression_fields(suppression)
        reason = suppression_reason_for(normalized_event, bounce_type)
        if reason
          suppress_deliveries!(
            found_by_id.values,
            reason: reason,
            provider: provider,
            configuration: configuration
          )
        end

        RecordingStudioNotifications::Delivery.transaction(requires_new: true) do
          updated_delivery_ids = []
          already_applied_delivery_ids = []

          found_by_id.each_value do |delivery|
            case apply_event!(delivery, event_type: normalized_event, occurred_at: occurred_at)
            when :updated
              updated_delivery_ids << delivery.id.to_s
            when :already_applied
              already_applied_delivery_ids << delivery.id.to_s
            end
          end

          WebhookUpdateResult.new(
            event_type: normalized_event,
            reference: resolved_reference,
            updated_delivery_ids: updated_delivery_ids.freeze,
            already_applied_delivery_ids: already_applied_delivery_ids.freeze,
            missing_delivery_ids: missing_delivery_ids.freeze
          )
        end
      end

      def process_webhook_event!(event:, configuration: RecordingStudioNotificationsEmail.configuration)
        webhook_event = normalize_webhook_event(event)

        mark_event_from_reference!(
          event_type: webhook_event.event_type,
          reference: webhook_event.reference,
          occurred_at: webhook_event.occurred_at,
          suppression: suppression_for(webhook_event.provider, webhook_event.bounce_type),
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

      def apply_event!(delivery, event_type:, occurred_at:)
        normalized_event = event_type.to_sym
        return apply_delivered!(delivery, occurred_at: occurred_at) if normalized_event == :delivered

        contract = EVENT_METHOD_CONTRACT.fetch(normalized_event)
        return :already_applied if email_event_applied?(delivery, normalized_event, contract)

        delivery.public_send(contract.fetch(:mutator), at: occurred_at)
        :updated
      end

      def apply_delivered!(delivery, occurred_at:)
        return :already_applied if delivery.respond_to?(:delivered?) && delivery.delivered?

        unless delivery.respond_to?(:mark_delivered!)
          raise UnsupportedWebhookEventError, unsupported_event_message(:delivered)
        end

        delivery.mark_delivered!(at: occurred_at)
        :updated
      end

      def email_event_applied?(delivery, event_type, contract)
        predicate = contract.fetch(:predicate)
        return delivery.public_send(predicate) if delivery.respond_to?(predicate)

        metadata = delivery.metadata if delivery.respond_to?(:metadata)
        return false unless metadata.respond_to?(:[])

        metadata[EMAIL_TIMESTAMP_KEYS.fetch(event_type)].present?
      end

      def suppression_for(provider, bounce_type = nil)
        { provider: provider, bounce_type: bounce_type }
      end

      def suppression_fields(suppression)
        return [nil, nil] if suppression.nil?

        [suppression[:provider], suppression[:bounce_type]]
      end

      def suppression_reason_for(event_type, bounce_type)
        return unless SUPPRESSION_REASONS.key?(event_type)
        return if event_type == :bounced && !BounceType.permanent?(bounce_type)

        SUPPRESSION_REASONS.fetch(event_type)
      end

      def unsupported_event_message(event_type)
        "delivery model does not support #{event_type} callbacks"
      end

      def suppress_deliveries!(deliveries, reason:, provider:, configuration:)
        normalized_provider = provider.to_s.strip
        normalized_provider = "email" if normalized_provider.empty?
        addresses = deliveries.flat_map do |delivery|
          addresses_for_delivery(delivery, configuration: configuration)
        end

        Suppression.transaction(requires_new: true) do
          addresses.each do |address|
            Suppression.suppress!(
              address: address,
              reason: reason,
              provider: normalized_provider
            )
          end
        end
      end

      def addresses_for_delivery(delivery, configuration:)
        notification = notification_for_delivery(delivery)
        recipient = notification.recipient if notification.respond_to?(:recipient)
        raise DeliveryError, "delivery recipient could not be resolved" if recipient.nil?

        Array(configuration.recipients.resolve(recipient))
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
