# frozen_string_literal: true

require "test_helper"

class DeliveryCallbacksTest < Minitest::Test
  Record = Struct.new(:id)

  class FakeDelivery
    attr_reader :id, :marked_at, :opened_at, :clicked_at, :bounced_at, :complained_at,
                :unsubscribed_at

    def initialize(id:, delivered: false)
      @id = id
      @delivered = delivered
    end

    def delivered?
      @delivered
    end

    def mark_delivered!(at:)
      @delivered = true
      @marked_at = at
    end

    def opened?
      !@opened_at.nil?
    end

    def clicked?
      !@clicked_at.nil?
    end

    def bounced?
      !@bounced_at.nil?
    end

    def complained?
      !@complained_at.nil?
    end

    def unsubscribed?
      !@unsubscribed_at.nil?
    end

    def mark_opened!(at:)
      @opened_at = at
    end

    def mark_clicked!(at:)
      @clicked_at = at
    end

    def mark_bounced!(at:)
      @bounced_at = at
    end

    def mark_complained!(at:)
      @complained_at = at
    end

    def mark_unsubscribed!(at:)
      @unsubscribed_at = at
    end
  end

  def setup
    @had_delivery_constant = RecordingStudioNotifications.const_defined?(:Delivery, false)
    @original_delivery_constant = RecordingStudioNotifications.const_get(:Delivery) if @had_delivery_constant
    unless @had_delivery_constant
      RecordingStudioNotifications.const_set(:Delivery, Class.new)
    end

    @configuration = RecordingStudioNotificationsEmail::Configuration.new
    @configuration.message_verifier = ActiveSupport::MessageVerifier.new("c" * 64, serializer: JSON)
    @delivered_at = Time.utc(2026, 7, 17, 12, 0, 0)
  end

  def teardown
    if @had_delivery_constant
      RecordingStudioNotifications.const_set(:Delivery, @original_delivery_constant)
    else
      RecordingStudioNotifications.send(:remove_const, :Delivery)
    end
  end

  def test_marks_pending_deliveries_from_signed_reference
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1")

    with_stubbed_delivery_where([delivery]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_delivered_from_reference!(
        reference: reference,
        delivered_at: @delivered_at,
        configuration: @configuration
      )

      assert_equal %w[delivery-1], result.updated_delivery_ids
      assert_equal [], result.already_delivered_ids
      assert_equal [], result.missing_delivery_ids
      assert_equal @delivered_at, delivery.marked_at
    end
  end

  def test_reports_missing_and_already_delivered_ids
    reference = RecordingStudioNotificationsEmail::Correlation::Reference.new(
      notification_ids: %w[notification-1 notification-2],
      delivery_ids: %w[delivery-1 delivery-2],
      rollup: true
    )
    already_delivered = FakeDelivery.new(id: "delivery-1", delivered: true)

    with_stubbed_delivery_where([already_delivered]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_delivered_from_reference!(
        reference: reference,
        delivered_at: @delivered_at,
        configuration: @configuration
      )

      assert_equal [], result.updated_delivery_ids
      assert_equal %w[delivery-1], result.already_delivered_ids
      assert_equal %w[delivery-2], result.missing_delivery_ids
    end
  end

  def test_invalid_reference_raises
    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_delivered_from_reference!(
        reference: "not-a-token",
        delivered_at: @delivered_at,
        configuration: @configuration
      )
    end
  end

  def test_marks_open_events_from_reference
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1")

    with_stubbed_delivery_where([delivery]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_opened_from_reference!(
        reference: reference,
        opened_at: @delivered_at,
        configuration: @configuration
      )

      assert_equal :opened, result.event_type
      assert_equal %w[delivery-1], result.updated_delivery_ids
      assert_equal [], result.already_applied_delivery_ids
      assert_equal @delivered_at, delivery.opened_at
    end
  end

  def test_repeated_event_is_reported_as_already_applied
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1")
    delivery.mark_clicked!(at: @delivered_at)

    with_stubbed_delivery_where([delivery]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_clicked_from_reference!(
        reference: reference,
        clicked_at: @delivered_at,
        configuration: @configuration
      )

      assert_equal [], result.updated_delivery_ids
      assert_equal %w[delivery-1], result.already_applied_delivery_ids
    end
  end

  def test_ingest_webhook_event_routes_to_matching_callback
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1")
    event = RecordingStudioNotificationsEmail::WebhookEvent.new(
      provider: :postmark,
      event_type: :bounced,
      reference: reference,
      occurred_at: @delivered_at,
      external_event_id: "event-1",
      external_message_id: "message-1",
      metadata: { "stream" => "outbound" }
    )

    with_stubbed_delivery_where([delivery]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.ingest_webhook_event!(
        event: event,
        configuration: @configuration
      )

      assert_equal :bounced, result.event_type
      assert_equal %w[delivery-1], result.updated_delivery_ids
      assert_equal @delivered_at, delivery.bounced_at
    end
  end

  def test_unsupported_event_for_delivery_model_raises
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = Object.new
    delivery.define_singleton_method(:id) { "delivery-1" }

    with_stubbed_delivery_where([delivery]) do
      error = assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
        RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_opened_from_reference!(
          reference: reference,
          opened_at: @delivered_at,
          configuration: @configuration
        )
      end

      assert_includes error.message, "opened"
    end
  end

  def test_public_api_delegates_to_delivery_callbacks
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1")
    original_configuration = RecordingStudioNotificationsEmail.instance_variable_get(:@configuration)

    with_stubbed_delivery_where([delivery]) do
      RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, @configuration)
      result = RecordingStudioNotificationsEmail.mark_delivered_from_reference!(
        reference: reference,
        delivered_at: @delivered_at
      )

      assert_equal %w[delivery-1], result.updated_delivery_ids
      assert_equal @delivered_at, delivery.marked_at
    end
  ensure
    RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, original_configuration)
  end

  def test_public_api_delegates_webhook_helpers
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1")
    original_configuration = RecordingStudioNotificationsEmail.instance_variable_get(:@configuration)

    with_stubbed_delivery_where([delivery]) do
      RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, @configuration)

      opened_result = RecordingStudioNotificationsEmail.mark_opened_from_reference!(
        reference: reference,
        opened_at: @delivered_at
      )
      assert_equal :opened, opened_result.event_type
      assert_equal @delivered_at, delivery.opened_at

      ingest_result = RecordingStudioNotificationsEmail.ingest_webhook_event!(
        event: {
          provider: :postmark,
          event_type: :unsubscribed,
          reference: reference,
          occurred_at: @delivered_at,
          metadata: {}
        }
      )
      assert_equal :unsubscribed, ingest_result.event_type
      assert_equal @delivered_at, delivery.unsubscribed_at
    end
  ensure
    RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, original_configuration)
  end

  private

  def signed_reference(notification_id:, delivery_id:)
    RecordingStudioNotificationsEmail::Correlation.sign(
      notification: Record.new(notification_id),
      delivery: Record.new(delivery_id),
      configuration: @configuration
    )
  end

  def with_stubbed_delivery_where(result)
    delivery_class = RecordingStudioNotifications::Delivery
    singleton = class << delivery_class; self; end
    had_where = singleton.method_defined?(:where)
    original_where = delivery_class.method(:where) if had_where

    singleton.send(:define_method, :where) { |_ids| result }
    yield
  ensure
    singleton.send(:remove_method, :where)
    singleton.send(:define_method, :where, original_where) if had_where
  end
end