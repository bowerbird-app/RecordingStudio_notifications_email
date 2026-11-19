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
      to = recipient_for(event)
      raise_if_suppressed!(to)
      thread_reference = thread_reference_for([notification])
      message = mailer.with(
        event: event,
        to: to,
        from: configured_from,
        reply_to: outbound_reply_to(notification, delivery),
        template_path: individual_template_path_for(event),
        tracked_notification_path: tracked_notification_path(notification),
        correlation_reference: reference,
        message_id: DeliveryToken.message_id(reference, configuration: @configuration),
        in_reply_to: thread_reference,
        references: thread_reference
      ).notification

      message.deliver_now
    end

    def deliver_rollup(notifications:, deliveries:, rollup_key:, cadence:, period_starts_at:, period_ends_at:,
                       idempotency_key: nil)
      notifications = Array(notifications)
      deliveries = Array(deliveries)
      raise ArgumentError, "notifications are required" if notifications.empty?
      raise ArgumentError, "deliveries must match notifications" unless notifications.size == deliveries.size

      events = notifications.zip(deliveries).map do |notification, delivery|
        Event.wrap(notification, delivery: delivery)
      end
      recipient_identities = events.map { |event| recipient_identity_key(event.recipient) }
      raise DeliveryError, "rollup notifications must resolve to one recipient" unless recipient_identities.uniq.one?

      recipients = events.map { |event| recipient_for(event) }
      raise DeliveryError, "rollup notifications must resolve to one email address" unless recipients.uniq.one?

      raise_if_suppressed!(recipients.first)
      template_path = rollup_template_path_for(events)
      thread_reference = thread_reference_for(notifications)

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
        reply_to: rollup_reply_to(notifications, deliveries),
        template_path: template_path,
        correlation_reference: reference,
        cadence: cadence,
        period_starts_at: period_starts_at,
        period_ends_at: period_ends_at,
        message_id: DeliveryToken.message_id(reference, configuration: @configuration),
        in_reply_to: thread_reference,
        references: thread_reference
      ).rollup

      message.deliver_now
    end

    private

    def mailer
      @configuration.resolve_mailer_class
    end

    def individual_template_path_for(event)
      template_path_for(
        event.notification_type,
        :individual_mailer,
        Configuration::DEFAULT_TEMPLATE
      )
    end

    def rollup_template_path_for(events)
      notification_types = events.map(&:notification_type).uniq
      raise DeliveryError, "rollup notifications must share one notification type" unless notification_types.one?

      template_path_for(
        notification_types.first,
        :rollup_mailer,
        Configuration::DEFAULT_ROLLUP_TEMPLATE
      )
    end

    def template_path_for(notification_type, attribute, default)
      definition = RecordingStudioNotifications.notification_types.fetch(notification_type)
      path = definition.channel_options.dig(:email, attribute).to_s.strip.presence
      path || default
    rescue KeyError
      default
    end

    def raise_if_suppressed!(addresses)
      Array(addresses).each do |address|
        next unless Suppression.suppressed?(address)

        raise SuppressedRecipientError, "email recipient is suppressed"
      end
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

    def outbound_reply_to(notification, delivery)
      address = per_delivery_reply_to(notification, delivery)
      return validate_mailbox!(address, "reply_to") if address

      configured_reply_to
    end

    def rollup_reply_to(notifications, deliveries)
      return outbound_reply_to(notifications.first, deliveries.first) if deliveries.one?

      configured_reply_to
    end

    def per_delivery_reply_to(notification, delivery)
      return unless replyable_notification?(notification)

      ReplyAddress.address_for(delivery, configuration: @configuration)
    end

    def replyable_notification?(notification)
      return false unless RecordingStudioNotifications.respond_to?(:replyable?)

      RecordingStudioNotifications.replyable?(notification.notification_type)
    end

    def thread_reference_for(notifications)
      keys = notifications.map { |notification| thread_key_for(notification) }
      return if keys.any?(&:blank?)
      return if keys.uniq.size != 1

      ThreadMessageId.for(keys.first, configuration: @configuration)
    end

    def thread_key_for(notification)
      return unless notification.respond_to?(:thread_key)

      notification.thread_key.to_s.strip.presence
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

    def tracked_notification_path(notification)
      RecordingStudioNotifications.notification_url(notification)
    rescue ActionController::UrlGenerationError
      nil
    end

    def recipient_identity_key(recipient)
      id = recipient.id if recipient.respond_to?(:id)
      if id.to_s.strip.present?
        [recipient.class.name.presence || recipient.class.to_s, id.to_s]
      else
        [:object, recipient.__id__]
      end
    end
  end
end
