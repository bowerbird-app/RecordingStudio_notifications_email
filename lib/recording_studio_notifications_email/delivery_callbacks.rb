# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module DeliveryCallbacks
    DeliveryUpdateResult = Data.define(
      :reference,
      :updated_delivery_ids,
      :already_delivered_ids,
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

      private

      def resolve_reference!(reference, configuration:)
        return reference if reference.is_a?(Correlation::Reference)

        Correlation.verify!(reference, configuration: configuration)
      end
    end
  end
end