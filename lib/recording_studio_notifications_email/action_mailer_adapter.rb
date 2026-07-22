# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  class DeliveryError < StandardError; end

  # Channel adapter for RecordingStudioNotifications. The parent delivery job
  # already owns async execution, retries, and delivery state, so this adapter
  # intentionally calls deliver_now.
  class ActionMailerAdapter
    def initialize(configuration: RecordingStudioNotificationsEmail.configuration)
      @configuration = configuration
    end

    def deliver(notification:, delivery:)
      event = Event.wrap(notification, delivery: delivery)
      reference = DeliveryToken.sign(notification: notification, delivery: delivery, configuration: @configuration)
      message = mailer.with(
        event: event,
        to: recipient_for(event),
        from: configured_from,
        reply_to: configured_reply_to,
        template_path: @configuration.template_for(event.notification_type),
        tracked_notification_path: tracked_notification_path(notification),
        correlation_reference: reference,
        message_id: DeliveryToken.message_id(reference, configuration: @configuration)
      ).notification

      message.deliver_now
    end

    def deliver_rollup(notifications:, deliveries:, rollup_key:, cadence:, period_starts_at:, period_ends_at:,
                       idempotency_key: nil)
      notifications = Array(notifications)
      deliveries = Array(deliveries)
      raise ArgumentError, "notifications are required" if notifications.empty?
      raise ArgumentError, "deliveries must match notifications" unless notifications.size == deliveries.size

      events = notifications.zip(deliveries).map { |notification, delivery| Event.wrap(notification, delivery: delivery) }
      recipient_identities = events.map { |event| recipient_identity_key(event.recipient) }
      unless recipient_identities.uniq.one?
        raise DeliveryError, "rollup notifications must resolve to one recipient"
      end

      recipients = events.map { |event| recipient_for(event) }
      unless recipients.uniq.one?
        raise DeliveryError, "rollup notifications must resolve to one email address"
      end

      reference = DeliveryToken.sign(
        notifications: notifications,
        deliveries: deliveries,
        rollup_key: rollup_key || idempotency_key,
        configuration: @configuration
      )
      message = mailer.with(
        events: events,
        to: recipients.first,
        from: configured_from,
        reply_to: configured_reply_to,
        template_path: @configuration.rollup_template,
        correlation_reference: reference,
        cadence: cadence,
        period_starts_at: period_starts_at,
        period_ends_at: period_ends_at,
        message_id: DeliveryToken.message_id(reference, configuration: @configuration)
      ).rollup

      message.deliver_now
    end

    private

    def mailer
      @configuration.resolve_mailer_class
    end

    def recipient_for(event)
      @configuration.recipients.resolve(event.recipient)
    rescue ArgumentError => e
      raise DeliveryError, e.message
    end

    def configured_from
      value = @configuration.from.to_s.presence ||
              raise(DeliveryError, "configure RecordingStudioNotificationsEmail.config.from")
      validate_mailbox!(value, "from")
    end

    def configured_reply_to
      return if @configuration.reply_to.blank?

      Array(@configuration.reply_to).map { |value| validate_mailbox!(value, "reply_to") }
                                   .then { |values| values.one? ? values.first : values }
    end

    def validate_mailbox!(value, label)
      address = value.to_s.strip
      parsed = Mail::Address.new(address)
      return address if !address.match?(/[\r\n]/) && parsed.address.present? && parsed.domain.present?

      raise DeliveryError, "#{label} must be a valid email address"
    rescue Mail::Field::ParseError
      raise DeliveryError, "#{label} must be a valid email address"
    end

    def recipient_identity_key(recipient)
      id = recipient.id if recipient.respond_to?(:id)
      if id.to_s.strip.present?
        [recipient.class.name.presence || recipient.class.to_s, id.to_s]
      else
        [:object, recipient.__id__]
      end
    end

    def tracked_notification_path(notification)
      RecordingStudioNotifications::Engine.routes.url_helpers.open_notification_path(notification.id)
    rescue StandardError
      nil
    end
  end

  module Adapters
    ActionMailerAdapter = RecordingStudioNotificationsEmail::ActionMailerAdapter
  end

  module Channels
    ActionMailerAdapter = RecordingStudioNotificationsEmail::ActionMailerAdapter
  end
end
