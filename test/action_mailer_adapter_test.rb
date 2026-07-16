# frozen_string_literal: true

require "test_helper"

class ActionMailerAdapterTest < Minitest::Test
  Recipient = Struct.new(:id, :email, keyword_init: true)
  Notification = Struct.new(:id, :notification_type, :title, :recipient, keyword_init: true)
  Delivery = Struct.new(:id)

  class FakeMessage
    attr_reader :delivered

    def deliver_now
      @delivered = true
      self
    end
  end

  class FakeMailer
    class << self
      attr_reader :params, :action

      def with(**params)
        @params = params
        self
      end

      def notification
        @action = :notification
        FakeMessage.new
      end

      def rollup
        @action = :rollup
        FakeMessage.new
      end
    end
  end

  def setup
    @configuration = RecordingStudioNotificationsEmail::Configuration.new
    @configuration.from = "notifications@example.test"
    @configuration.mailer_class = FakeMailer
    @configuration.message_verifier = ActiveSupport::MessageVerifier.new("b" * 64, serializer: JSON)
    @configuration.message_id_domain = "mail.example.test"
    @adapter = RecordingStudioNotificationsEmail::ActionMailerAdapter.new(configuration: @configuration)
  end

  def test_delivers_with_normalized_event_and_signed_reference
    notification = build_notification

    message = @adapter.deliver(notification: notification, delivery: Delivery.new("delivery-1"))

    assert message.delivered
    assert_equal :notification, FakeMailer.action
    assert_equal "person@example.test", FakeMailer.params.fetch(:to)
    assert_equal "notifications@example.test", FakeMailer.params.fetch(:from)
    assert_instance_of RecordingStudioNotificationsEmail::Event, FakeMailer.params.fetch(:event)
    assert RecordingStudioNotificationsEmail::Correlation.verify(
      FakeMailer.params.fetch(:correlation_reference),
      configuration: @configuration
    )
  end

  def test_missing_from_fails_before_sending
    @configuration.from = nil

    error = assert_raises(RecordingStudioNotificationsEmail::DeliveryError) do
      @adapter.deliver(notification: build_notification, delivery: Delivery.new("delivery-1"))
    end

    assert_match(/configure .*from/, error.message)
  end

  def test_invalid_from_or_reply_to_is_rejected
    @configuration.from = "not-an-address"
    assert_raises(RecordingStudioNotificationsEmail::DeliveryError) do
      @adapter.deliver(notification: build_notification, delivery: Delivery.new("delivery-1"))
    end

    @configuration.from = "notifications@example.test"
    @configuration.reply_to = "support@example.test\nBcc: victim@example.test"
    assert_raises(RecordingStudioNotificationsEmail::DeliveryError) do
      @adapter.deliver(notification: build_notification, delivery: Delivery.new("delivery-1"))
    end
  end

  def test_missing_recipient_email_fails_explicitly
    notification = build_notification(recipient: Recipient.new(email: nil))

    assert_raises(RecordingStudioNotificationsEmail::DeliveryError) do
      @adapter.deliver(notification: notification, delivery: Delivery.new("delivery-1"))
    end
  end

  def test_rollup_requires_matching_notifications_and_deliveries
    assert_raises(ArgumentError) do
      @adapter.deliver_rollup(
        notifications: [build_notification],
        deliveries: [],
        rollup_key: "weekly/person",
        cadence: :weekly,
        period_starts_at: Time.now,
        period_ends_at: Time.now,
        idempotency_key: "weekly/person"
      )
    end
  end

  def test_rollup_delivers_one_message_for_one_recipient
    recipient = Recipient.new(id: "person-1", email: "person@example.test")
    notifications = [
      build_notification(id: "notification-1", recipient: recipient),
      build_notification(id: "notification-2", recipient: recipient)
    ]
    deliveries = [Delivery.new("delivery-1"), Delivery.new("delivery-2")]

    message = @adapter.deliver_rollup(
      notifications: notifications,
      deliveries: deliveries,
      rollup_key: "weekly/person",
      cadence: :weekly,
      period_starts_at: Time.now,
      period_ends_at: Time.now,
      idempotency_key: "weekly/person"
    )

    assert message.delivered
    assert_equal :rollup, FakeMailer.action
    assert_equal 2, FakeMailer.params.fetch(:events).size
    reference = RecordingStudioNotificationsEmail::Correlation.verify(
      FakeMailer.params.fetch(:correlation_reference),
      configuration: @configuration
    )
    assert_equal %w[notification-1 notification-2], reference.notification_ids
    assert_equal %w[delivery-1 delivery-2], reference.delivery_ids
    assert_match(/\A<rsne-[0-9a-f]{64}@mail\.example\.test>\z/, FakeMailer.params.fetch(:message_id))
  end

  def test_rollup_canonicalizes_multi_address_recipients
    recipient = Recipient.new(id: "team-1", email: ["one@example.test", "two@example.test"])
    notifications = [
      build_notification(
        id: "notification-1",
        recipient: recipient
      ),
      build_notification(
        id: "notification-2",
        recipient: recipient
      )
    ]

    message = @adapter.deliver_rollup(
      notifications: notifications,
      deliveries: [Delivery.new("delivery-1"), Delivery.new("delivery-2")],
      rollup_key: "weekly/team",
      cadence: :weekly,
      period_starts_at: Time.now,
      period_ends_at: Time.now,
      idempotency_key: "weekly/team"
    )

    assert message.delivered
  end

  def test_rollup_rejects_distinct_recipients_even_when_emails_match
    notifications = [
      build_notification(
        id: "notification-1",
        recipient: Recipient.new(id: "person-1", email: "person@example.test")
      ),
      build_notification(
        id: "notification-2",
        recipient: Recipient.new(id: "person-2", email: "person@example.test")
      )
    ]

    assert_raises(RecordingStudioNotificationsEmail::DeliveryError) do
      @adapter.deliver_rollup(
        notifications: notifications,
        deliveries: [Delivery.new("delivery-1"), Delivery.new("delivery-2")],
        rollup_key: "weekly/person",
        cadence: :weekly,
        period_starts_at: Time.now,
        period_ends_at: Time.now,
        idempotency_key: "weekly/person"
      )
    end
  end

  def test_rollup_rejects_equivalent_recipients_with_conflicting_addresses
    notifications = [
      build_notification(
        id: "notification-1",
        recipient: Recipient.new(id: "person-1", email: "current@example.test")
      ),
      build_notification(
        id: "notification-2",
        recipient: Recipient.new(id: "person-1", email: "stale@example.test")
      )
    ]

    error = assert_raises(RecordingStudioNotificationsEmail::DeliveryError) do
      @adapter.deliver_rollup(
        notifications: notifications,
        deliveries: [Delivery.new("delivery-1"), Delivery.new("delivery-2")],
        rollup_key: "weekly/person",
        cadence: :weekly,
        period_starts_at: Time.now,
        period_ends_at: Time.now,
        idempotency_key: "weekly/person"
      )
    end

    assert_match(/one email address/, error.message)
  end

  private

  def build_notification(id: "notification-1", recipient: Recipient.new(email: "person@example.test"))
    Notification.new(id: id, notification_type: :comment, title: "Comment", recipient: recipient)
  end
end
