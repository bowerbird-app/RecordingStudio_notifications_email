# frozen_string_literal: true

require "test_helper"

class CorrelationTest < Minitest::Test
  Record = Struct.new(:id)

  def setup
    @original_configuration = RecordingStudioNotificationsEmail.instance_variable_get(:@configuration)
    @original_adapter = RecordingStudioNotificationsEmail.instance_variable_get(:@adapter)
    RecordingStudioNotificationsEmail.reset_configuration!
    RecordingStudioNotificationsEmail.configuration.message_verifier =
      ActiveSupport::MessageVerifier.new("a" * 64, serializer: JSON)
  end

  def teardown
    RecordingStudioNotificationsEmail.instance_variable_set(:@configuration, @original_configuration)
    RecordingStudioNotificationsEmail.instance_variable_set(:@adapter, @original_adapter)
  end

  def test_signed_reference_round_trips_ids
    token = RecordingStudioNotificationsEmail::Correlation.sign(
      notification: Record.new("notification-1"),
      delivery: Record.new("delivery-1")
    )

    reference = RecordingStudioNotificationsEmail::Correlation.verify!(token)

    assert_equal ["notification-1"], reference.notification_ids
    assert_equal "notification-1", reference.notification_id
    assert_equal "delivery-1", reference.delivery_id
    refute reference.rollup?
  end

  def test_tampered_reference_is_rejected
    token = RecordingStudioNotificationsEmail::Correlation.sign(
      notification: Record.new("notification-1"),
      delivery: Record.new("delivery-1")
    )

    assert_nil RecordingStudioNotificationsEmail::Correlation.verify("#{token}tampered")
    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      RecordingStudioNotificationsEmail::Correlation.verify!("#{token}tampered")
    end
  end

  def test_rollup_reference_records_all_deliveries_without_loading_models
    token = RecordingStudioNotificationsEmail::Correlation.sign(
      notifications: [Record.new("notification-1"), Record.new("notification-2")],
      deliveries: [Record.new("delivery-1"), Record.new("delivery-2")],
      rollup_key: "weekly/user-1"
    )

    reference = RecordingStudioNotificationsEmail::Correlation.verify!(token)
    payload = RecordingStudioNotificationsEmail.configuration.message_verifier.verified(
      token,
      purpose: RecordingStudioNotificationsEmail::Correlation::PURPOSE
    )

    assert_equal %w[notification-1 notification-2], reference.notification_ids
    assert_equal %w[delivery-1 delivery-2], reference.delivery_ids
    assert reference.rollup?
    assert_equal true, payload["rollup"]
    refute payload.key?("rollup_key")
    refute_includes token, "weekly/user-1"
  end

  def test_records_without_ids_are_rejected
    assert_raises(ArgumentError) do
      RecordingStudioNotificationsEmail::Correlation.sign(
        notification: Record.new(nil),
        delivery: Record.new("delivery-1")
      )
    end
  end

  def test_a_delivery_is_required
    assert_raises(ArgumentError) do
      RecordingStudioNotificationsEmail::Correlation.sign(notification: Record.new("notification-1"))
    end
  end

  def test_notifications_and_deliveries_must_align
    assert_raises(ArgumentError) do
      RecordingStudioNotificationsEmail::Correlation.sign(
        notifications: [Record.new("notification-1"), Record.new("notification-2")],
        deliveries: [Record.new("delivery-1")]
      )
    end
  end

  def test_expired_reference_uses_soft_and_strict_failure_modes
    token = RecordingStudioNotificationsEmail.configuration.message_verifier.generate(
      {
        "notification_ids" => ["notification-1"],
        "delivery_ids" => ["delivery-1"],
        "rollup" => false
      },
      purpose: RecordingStudioNotificationsEmail::Correlation::PURPOSE,
      expires_in: -1.second
    )

    assert_nil RecordingStudioNotificationsEmail::Correlation.verify(token)
    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      RecordingStudioNotificationsEmail::Correlation.verify!(token)
    end
  end

  def test_non_positive_or_missing_expiry_is_rejected
    [nil, 0, -1, "one day"].each do |value|
      RecordingStudioNotificationsEmail.configuration.signed_reference_expires_in = value

      assert_raises(RecordingStudioNotificationsEmail::ConfigurationError) do
        RecordingStudioNotificationsEmail::Correlation.sign(
          notification: Record.new("notification-1"),
          delivery: Record.new("delivery-1")
        )
      end
    end
  end

  def test_message_id_is_stable_and_rejects_an_invalid_domain
    RecordingStudioNotificationsEmail.configuration.message_id_domain = "mail.example.test"
    first_token = RecordingStudioNotificationsEmail::Correlation.sign(
      notifications: [Record.new("notification-1"), Record.new("notification-2")],
      deliveries: [Record.new("delivery-1"), Record.new("delivery-2")]
    )
    second_token = RecordingStudioNotificationsEmail::Correlation.sign(
      notifications: [Record.new("notification-1"), Record.new("notification-2")],
      deliveries: [Record.new("delivery-1"), Record.new("delivery-2")]
    )

    assert_equal(
      RecordingStudioNotificationsEmail::Correlation.message_id(first_token),
      RecordingStudioNotificationsEmail::Correlation.message_id(second_token)
    )

    RecordingStudioNotificationsEmail.configuration.message_id_domain = "invalid\nBcc"
    assert_raises(RecordingStudioNotificationsEmail::ConfigurationError) do
      RecordingStudioNotificationsEmail::Correlation.message_id(first_token)
    end

    %w[example..test -example.test example-.test .example.test].each do |domain|
      RecordingStudioNotificationsEmail.configuration.message_id_domain = domain
      assert_raises(RecordingStudioNotificationsEmail::ConfigurationError) do
        RecordingStudioNotificationsEmail::Correlation.message_id(first_token)
      end
    end
  end

  def test_verify_accepts_legacy_singular_payload
    token = RecordingStudioNotificationsEmail.configuration.message_verifier.generate(
      {
        "notification_id" => "notification-legacy",
        "delivery_id" => "delivery-legacy",
        "rollup" => false
      },
      purpose: RecordingStudioNotificationsEmail::Correlation::PURPOSE,
      expires_in: 1.hour
    )

    reference = RecordingStudioNotificationsEmail::Correlation.verify!(token)

    assert_equal ["notification-legacy"], reference.notification_ids
    assert_equal "notification-legacy", reference.notification_id
    assert_equal ["delivery-legacy"], reference.delivery_ids
    assert_equal "delivery-legacy", reference.delivery_id
  end
end
