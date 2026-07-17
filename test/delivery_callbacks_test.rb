# frozen_string_literal: true

require "test_helper"

class DeliveryCallbacksTest < Minitest::Test
  Record = Struct.new(:id)

  class FakeDelivery
    attr_reader :id, :marked_at

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