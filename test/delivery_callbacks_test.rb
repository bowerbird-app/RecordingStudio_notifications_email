# frozen_string_literal: true

require "test_helper"

class DeliveryCallbacksTest < Minitest::Test
  Record = Struct.new(:id)
  FakeNotification = Struct.new(:id, :read_at) do
    attr_reader :saved

    def save!
      @saved = true
    end

    def saved?
      !!@saved
    end
  end

  class ContractAwareDelivery
    attr_reader :id, :called_mutators, :called_predicates

    def initialize(id:)
      @id = id
      @called_mutators = []
      @called_predicates = []
    end

    def email_opened?
      @called_predicates << :email_opened?
      false
    end

    def opened?
      @called_predicates << :opened?
      false
    end

    def mark_email_opened!(at:)
      @called_mutators << [:mark_email_opened!, at]
    end

    def mark_opened!(at:)
      @called_mutators << [:mark_opened!, at]
    end
  end

  class FakeDelivery
    attr_reader :id, :marked_at, :opened_at, :clicked_at, :bounced_at, :complained_at,
                :unsubscribed_at, :notification

    def initialize(id:, delivered: false, notification: nil)
      @id = id
      @delivered = delivered
      @notification = notification
    end

    def delivered?
      @delivered
    end

    def mark_delivered!(at:)
      @delivered = true
      @marked_at = at
    end

    def email_opened?
      !@opened_at.nil?
    end

    def email_clicked?
      !@clicked_at.nil?
    end

    def email_bounced?
      !@bounced_at.nil?
    end

    def email_complained?
      !@complained_at.nil?
    end

    def email_unsubscribed?
      !@unsubscribed_at.nil?
    end

    def mark_email_opened!(at:)
      @opened_at = at
    end

    def mark_email_clicked!(at:)
      @clicked_at = at
    end

    def mark_email_bounced!(at:)
      @bounced_at = at
    end

    def mark_email_complained!(at:)
      @complained_at = at
    end

    def mark_email_unsubscribed!(at:)
      @unsubscribed_at = at
    end
  end

  class LegacyDelivery
    attr_reader :id, :status, :error_message, :notification, :opened_at

    def initialize(id:, status: "delivered", notification: nil)
      @id = id
      @status = status
      @notification = notification
    end

    def delivered?
      @status == "delivered"
    end

    def failed?
      @status == "failed"
    end

    def mark_failed!(error = nil)
      @status = "failed"
      message = error.respond_to?(:message) ? error.message.to_s : error.to_s
      @error_message = message
    end

    def mark_opened!(at:)
      @opened_at = at
    end
  end

  class DeliveryWithoutOpenedCallbacks
    attr_reader :id, :notification

    def initialize(id:, notification:)
      @id = id
      @notification = notification
    end
  end

  def setup
    @had_delivery_constant = RecordingStudioNotifications.const_defined?(:Delivery, false)
    @original_delivery_constant = RecordingStudioNotifications.const_get(:Delivery) if @had_delivery_constant
    RecordingStudioNotifications.const_set(:Delivery, Class.new) unless @had_delivery_constant

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
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_delivered!(
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
    reference = RecordingStudioNotificationsEmail::DeliveryToken::Reference.new(
      notification_ids: %w[notification-1 notification-2],
      delivery_ids: %w[delivery-1 delivery-2],
      rollup: true
    )
    already_delivered = FakeDelivery.new(id: "delivery-1", delivered: true)

    with_stubbed_delivery_where([already_delivered]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_delivered!(
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
      RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_delivered!(
        reference: "not-a-token",
        delivered_at: @delivered_at,
        configuration: @configuration
      )
    end
  end

  def test_marks_open_events_from_reference
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    notification = FakeNotification.new("notification-1", nil)
    delivery = FakeDelivery.new(id: "delivery-1", notification: notification)

    with_stubbed_delivery_where([delivery]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_opened!(
        reference: reference,
        opened_at: @delivered_at,
        configuration: @configuration
      )

      assert_equal :opened, result.event_type
      assert_equal %w[delivery-1], result.updated_delivery_ids
      assert_equal [], result.already_applied_delivery_ids
      assert_equal @delivered_at, delivery.opened_at
      assert_nil notification.read_at
      refute notification.saved?
    end
  end

  def test_repeated_event_is_reported_as_already_applied
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1")
    delivery.mark_email_clicked!(at: @delivered_at)

    with_stubbed_delivery_where([delivery]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_clicked!(
        reference: reference,
        clicked_at: @delivered_at,
        configuration: @configuration
      )

      assert_equal [], result.updated_delivery_ids
      assert_equal %w[delivery-1], result.already_applied_delivery_ids
    end
  end

  def test_process_webhook_event_routes_to_matching_callback
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = FakeDelivery.new(id: "delivery-1", notification: notification)
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
      with_recorded_suppressions do |calls|
        result = RecordingStudioNotificationsEmail::DeliveryCallbacks.process_webhook_event!(
          event: event,
          configuration: @configuration
        )

        assert_equal :bounced, result.event_type
        assert_equal %w[delivery-1], result.updated_delivery_ids
        assert_equal @delivered_at, delivery.bounced_at
        assert_equal [{ address: "person@example.test", reason: "bounce", provider: "postmark" }], calls
      end
    end
  end

  def test_opened_without_canonical_mutator_raises_and_does_not_mark_notification_read
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    notification = FakeNotification.new("notification-1", nil)
    delivery = DeliveryWithoutOpenedCallbacks.new(id: "delivery-1", notification: notification)

    with_stubbed_delivery_where([delivery]) do
      error = assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
        RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_opened!(
          reference: reference,
          opened_at: @delivered_at,
          configuration: @configuration
        )
      end

      assert_includes error.message, "opened"
      assert_nil notification.read_at
      refute notification.saved?
    end
  end

  def test_legacy_aliases_are_not_used_for_bounce_or_open
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("Person <person@example.test>")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = LegacyDelivery.new(id: "delivery-1", notification: notification)

    with_stubbed_delivery_where([delivery]) do
      with_recorded_suppressions do |calls|
        error = assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
          RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_bounced!(
            reference: reference,
            bounced_at: @delivered_at,
            provider: :postmark,
            configuration: @configuration
          )
        end

        assert_includes error.message, "bounced"
        assert_equal "delivered", delivery.status
        assert_nil delivery.error_message
        assert_equal [{ address: "Person <person@example.test>", reason: "bounce", provider: "postmark" }], calls
      end

      error = assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
        RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_opened!(
          reference: reference,
          opened_at: @delivered_at,
          configuration: @configuration
        )
      end

      assert_includes error.message, "opened"
      assert_nil delivery.opened_at
    end
  end

  def test_complaint_suppression_is_committed_before_the_delivery_transaction
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = LegacyDelivery.new(id: "delivery-1", status: "pending", notification: notification)
    order = []

    with_stubbed_delivery_where([delivery], on_transaction: -> { order << :delivery }) do
      with_recorded_suppressions(on_transaction: -> { order << :suppression }) do
        assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
          RecordingStudioNotificationsEmail::DeliveryCallbacks.process_webhook_event!(
            event: {
              provider: :postmark,
              event_type: :complained,
              reference: reference,
              occurred_at: @delivered_at,
              metadata: {}
            },
            configuration: @configuration
          )
        end
      end
    end

    assert_equal %i[suppression delivery], order
    assert_equal "pending", delivery.status
  end

  def test_rollup_delivery_updates_share_one_transaction
    reference = RecordingStudioNotificationsEmail::DeliveryToken::Reference.new(
      notification_ids: %w[notification-1 notification-2],
      delivery_ids: %w[delivery-1 delivery-2],
      rollup: true
    )
    first = FakeDelivery.new(id: "delivery-1")
    second = FakeDelivery.new(id: "delivery-2")
    calls = 0

    with_stubbed_delivery_where([first, second], on_transaction: -> { calls += 1 }) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_delivered!(
        reference: reference,
        delivered_at: @delivered_at,
        configuration: @configuration
      )

      assert_equal %w[delivery-1 delivery-2], result.updated_delivery_ids
    end

    assert_equal 1, calls
  end

  def test_soft_bounce_updates_the_delivery_without_a_suppression
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = FakeDelivery.new(id: "delivery-1", notification: notification)

    with_stubbed_delivery_where([delivery]) do
      with_recorded_suppressions do |calls|
        result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_bounced!(
          reference: reference,
          bounced_at: @delivered_at,
          provider: :postmark,
          bounce_type: "Transient",
          configuration: @configuration
        )

        assert_equal %w[delivery-1], result.updated_delivery_ids
        assert_equal @delivered_at, delivery.bounced_at
        assert_empty calls
      end
    end
  end

  def test_hard_bounce_alias_from_a_webhook_suppresses
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = FakeDelivery.new(id: "delivery-1", notification: notification)

    with_stubbed_delivery_where([delivery]) do
      with_recorded_suppressions do |calls|
        RecordingStudioNotificationsEmail::DeliveryCallbacks.process_webhook_event!(
          event: {
            provider: :postmark,
            event_type: :bounced,
            reference: reference,
            occurred_at: @delivered_at,
            bounce_type: "HardBounce",
            metadata: {}
          },
          configuration: @configuration
        )

        assert_equal "bounce", calls.first.fetch(:reason)
      end
    end
  end

  def test_unknown_bounce_type_is_rejected_before_suppression
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = FakeDelivery.new(id: "delivery-1", notification: notification)

    with_stubbed_delivery_where([delivery]) do
      with_recorded_suppressions do |calls|
        error = assert_raises(RecordingStudioNotificationsEmail::InvalidWebhookPayloadError) do
          RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_bounced!(
            reference: reference,
            bounced_at: @delivered_at,
            bounce_type: "undetermined",
            configuration: @configuration
          )
        end

        assert_includes error.message, "undetermined"
        assert_empty calls
        assert_nil delivery.bounced_at
      end
    end
  end

  def test_unsubscribe_suppression_is_written_when_the_mutator_is_missing
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = LegacyDelivery.new(id: "delivery-1", notification: notification)

    with_stubbed_delivery_where([delivery]) do
      with_recorded_suppressions do |calls|
        assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
          RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_unsubscribed!(
            reference: reference,
            unsubscribed_at: @delivered_at,
            provider: :postmark,
            configuration: @configuration
          )
        end

        assert_equal [{ address: "person@example.test", reason: "unsubscribed", provider: "postmark" }], calls
        assert_nil delivery.opened_at
      end
    end
  end

  def test_blank_provider_is_stored_as_email
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = FakeDelivery.new(id: "delivery-1", notification: notification)

    with_stubbed_delivery_where([delivery]) do
      with_recorded_suppressions do |calls|
        RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_bounced!(
          reference: reference,
          bounced_at: @delivered_at,
          configuration: @configuration
        )

        assert_equal "email", calls.first.fetch(:provider)
        assert_equal "bounce", calls.first.fetch(:reason)
      end
    end
  end

  def test_bounce_without_a_resolvable_recipient_raises
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = LegacyDelivery.new(id: "delivery-1", notification: FakeNotification.new("notification-1", nil))

    with_stubbed_delivery_where([delivery]) do
      error = assert_raises(RecordingStudioNotificationsEmail::DeliveryError) do
        RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_bounced!(
          reference: reference,
          bounced_at: @delivered_at,
          provider: :postmark,
          configuration: @configuration
        )
      end

      assert_includes error.message, "recipient could not be resolved"
      assert_equal "delivered", delivery.status
    end
  end

  def test_unsupported_non_opened_event_for_delivery_model_raises
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = Object.new
    delivery.define_singleton_method(:id) { "delivery-1" }

    with_stubbed_delivery_where([delivery]) do
      error = assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
        RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_clicked!(
          reference: reference,
          clicked_at: @delivered_at,
          configuration: @configuration
        )
      end

      assert_includes error.message, "clicked"
    end
  end

  def test_prefers_canonical_contract_methods_over_aliases
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = ContractAwareDelivery.new(id: "delivery-1")

    with_stubbed_delivery_where([delivery]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_opened!(
        reference: reference,
        opened_at: @delivered_at,
        configuration: @configuration
      )

      assert_equal :opened, result.event_type
      assert_equal [:email_opened?], delivery.called_predicates
      assert_equal [[:mark_email_opened!, @delivered_at]], delivery.called_mutators
    end
  end

  def test_delivered_webhook_uses_the_canonical_mutator
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1", delivered: true)

    with_stubbed_delivery_where([delivery]) do
      result = RecordingStudioNotificationsEmail::DeliveryCallbacks.process_webhook_event!(
        event: {
          provider: :postmark,
          event_type: :delivered,
          reference: reference,
          occurred_at: @delivered_at,
          metadata: {}
        },
        configuration: @configuration
      )

      assert_equal %w[delivery-1], result.already_applied_delivery_ids
    end
  end

  def test_delivered_webhook_without_a_mutator_raises
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = Object.new
    delivery.define_singleton_method(:id) { "delivery-1" }
    delivery.define_singleton_method(:delivered?) { false }

    with_stubbed_delivery_where([delivery]) do
      error = assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
        RecordingStudioNotificationsEmail::DeliveryCallbacks.process_webhook_event!(
          event: {
            provider: :postmark,
            event_type: :delivered,
            reference: reference,
            occurred_at: @delivered_at,
            metadata: {}
          },
          configuration: @configuration
        )
      end

      assert_includes error.message, "delivered"
    end
  end

  def test_bounce_looks_up_the_notification_when_the_delivery_does_not_expose_it
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = Object.new
    delivery.define_singleton_method(:id) { "delivery-1" }
    delivery.define_singleton_method(:notification_id) { "notification-1" }
    delivery.define_singleton_method(:email_bounced?) { false }
    delivery.define_singleton_method(:mark_email_bounced!) { |at:| }

    had_notification = RecordingStudioNotifications.const_defined?(:Notification, false)
    original_notification = RecordingStudioNotifications.const_get(:Notification) if had_notification
    notification_class = Class.new do
      define_singleton_method(:find_by) { |id:| id == "notification-1" ? notification : nil }
    end
    RecordingStudioNotifications.const_set(:Notification, notification_class)

    with_stubbed_delivery_where([delivery]) do
      with_recorded_suppressions do |calls|
        RecordingStudioNotificationsEmail::DeliveryCallbacks.mark_bounced!(
          reference: reference,
          bounced_at: @delivered_at,
          provider: :postmark,
          configuration: @configuration
        )

        assert_equal "person@example.test", calls.first.fetch(:address)
      end
    end
  ensure
    if had_notification
      RecordingStudioNotifications.const_set(:Notification, original_notification)
    elsif RecordingStudioNotifications.const_defined?(:Notification, false)
      RecordingStudioNotifications.send(:remove_const, :Notification)
    end
  end

  def test_public_api_delegates_to_delivery_callbacks
    reference = signed_reference(notification_id: "notification-1", delivery_id: "delivery-1")
    delivery = FakeDelivery.new(id: "delivery-1")
    original_configuration = RecordingStudioNotificationsEmail.instance_variable_get(:@configuration)

    with_stubbed_delivery_where([delivery]) do
      RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, @configuration)
      result = RecordingStudioNotificationsEmail.mark_delivered!(
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
    recipient = Struct.new(:email).new("person@example.test")
    notification = FakeNotification.new("notification-1", nil)
    notification.define_singleton_method(:recipient) { recipient }
    delivery = FakeDelivery.new(id: "delivery-1", notification: notification)
    original_configuration = RecordingStudioNotificationsEmail.instance_variable_get(:@configuration)

    with_stubbed_delivery_where([delivery]) do
      RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, @configuration)

      opened_result = RecordingStudioNotificationsEmail.mark_opened!(
        reference: reference,
        opened_at: @delivered_at
      )
      assert_equal :opened, opened_result.event_type
      assert_equal @delivered_at, delivery.opened_at

      clicked_result = RecordingStudioNotificationsEmail.mark_clicked!(
        reference: reference,
        clicked_at: @delivered_at
      )
      assert_equal :clicked, clicked_result.event_type

      with_recorded_suppressions do |calls|
        unsubscribed_result = RecordingStudioNotificationsEmail.mark_unsubscribed!(
          reference: reference,
          unsubscribed_at: @delivered_at,
          provider: :postmark
        )
        assert_equal :unsubscribed, unsubscribed_result.event_type
        assert_equal "unsubscribed", calls.last.fetch(:reason)

        bounced_result = RecordingStudioNotificationsEmail.mark_bounced!(
          reference: reference,
          bounced_at: @delivered_at,
          provider: :postmark
        )
        assert_equal :bounced, bounced_result.event_type

        complained_result = RecordingStudioNotificationsEmail.mark_complained!(
          reference: reference,
          complained_at: @delivered_at,
          provider: :postmark
        )
        assert_equal :complained, complained_result.event_type

        process_result = RecordingStudioNotificationsEmail.process_webhook_event!(
          event: {
            provider: :postmark,
            event_type: :unsubscribed,
            reference: reference,
            occurred_at: @delivered_at,
            metadata: {}
          }
        )
        assert_equal :unsubscribed, process_result.event_type
        assert_equal @delivered_at, delivery.unsubscribed_at

        process_result = RecordingStudioNotificationsEmail.process_webhook_event!(
          event: {
            provider: :postmark,
            event_type: :unsubscribed,
            reference: reference,
            occurred_at: @delivered_at,
            metadata: {}
          }
        )
        assert_equal :unsubscribed, process_result.event_type
        assert_equal @delivered_at, delivery.unsubscribed_at
      end
    end
  ensure
    RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, original_configuration)
  end

  private

  def signed_reference(notification_id:, delivery_id:)
    RecordingStudioNotificationsEmail::DeliveryToken.sign(
      notification: Record.new(notification_id),
      delivery: Record.new(delivery_id),
      configuration: @configuration
    )
  end

  def with_stubbed_delivery_where(result, on_transaction: nil)
    delivery_class = RecordingStudioNotifications::Delivery
    singleton = class << delivery_class; self; end
    had_where = singleton.method_defined?(:where)
    original_where = delivery_class.method(:where) if had_where
    had_transaction = singleton.method_defined?(:transaction)
    original_transaction = delivery_class.method(:transaction) if had_transaction

    singleton.send(:define_method, :where) { |_ids| result }
    singleton.send(:define_method, :transaction) do |**_, &block|
      on_transaction&.call
      block.call
    end
    yield
  ensure
    singleton.send(:remove_method, :where)
    singleton.send(:define_method, :where, original_where) if had_where
    singleton.send(:remove_method, :transaction)
    singleton.send(:define_method, :transaction, original_transaction) if had_transaction
  end

  def with_recorded_suppressions(on_transaction: nil)
    calls = []
    suppressor = RecordingStudioNotificationsEmail::Suppression
    singleton = class << suppressor; self; end
    original_transaction = suppressor.method(:transaction)
    original_suppress = suppressor.method(:suppress!)
    singleton.send(:define_method, :transaction) do |**_, &block|
      on_transaction&.call
      block.call
    end
    singleton.send(:define_method, :suppress!) { |**kwargs| calls << kwargs }
    yield calls
  ensure
    singleton.send(:remove_method, :transaction)
    singleton.send(:define_method, :transaction, original_transaction)
    singleton.send(:remove_method, :suppress!)
    singleton.send(:define_method, :suppress!, original_suppress)
  end
end
