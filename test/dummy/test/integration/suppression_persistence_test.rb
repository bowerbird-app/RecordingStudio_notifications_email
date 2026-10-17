# frozen_string_literal: true

require "test_helper"

class SuppressionPersistenceTest < ActiveSupport::TestCase
  ADDRESS = "bounce-suppress@example.com"

  setup do
    @user = User.create!(
      email: ADDRESS,
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @notification = RecordingStudioNotifications.notify(
      notification_type: :system_announcement,
      recipient: @user,
      actor: @user,
      title: "Suppression target",
      body: "Fake address only.",
      channels: [:email],
      idempotency_key: "suppression/#{SecureRandom.uuid}"
    )
    @delivery = RecordingStudioNotifications::Delivery.find_by!(
      notification_id: @notification.id,
      channel: "email"
    )
    @reference = RecordingStudioNotificationsEmail::DeliveryToken.sign(
      notification: @notification,
      delivery: @delivery
    )
    @original_status = @delivery.status
  end

  teardown do
    delivery_class = RecordingStudioNotifications::Delivery
    delivery_class.send(:remove_method, :mark_email_bounced!) if delivery_class.method_defined?(:mark_email_bounced!)
  end

  test "schema has the address suppression table" do
    assert ActiveRecord::Base.connection.table_exists?(:recording_studio_notifications_email_suppressions)
    assert ActiveRecord::Base.connection.index_exists?(
      :recording_studio_notifications_email_suppressions,
      :address,
      unique: true,
      name: "idx_rsne_suppressions_address"
    )
  end

  test "bounce suppression remains when the delivery update rolls back" do
    RecordingStudioNotifications::Delivery.class_eval do
      def mark_email_bounced!(at:)
        update!(status: "failed", error_message: "should roll back")
        raise "after write"
      end
    end

    assert_raises(RuntimeError) do
      RecordingStudioNotificationsEmail.mark_bounced!(
        reference: @reference,
        provider: "postmark",
        bounce_type: "permanent"
      )
    end

    @delivery.reload
    assert_equal @original_status, @delivery.status
    assert_nil @delivery.error_message
    assert RecordingStudioNotificationsEmail::Suppression.suppressed?("Person <#{ADDRESS}>")

    record = RecordingStudioNotificationsEmail::Suppression.find_by!(address: ADDRESS)
    assert_equal "bounce", record.reason
    assert_equal "postmark", record.provider
    assert_nil record.lifted_at

    lifted_at = Time.utc(2026, 10, 16, 12, 0, 0)
    RecordingStudioNotificationsEmail::Suppression.lift!(ADDRESS, at: lifted_at)
    refute RecordingStudioNotificationsEmail::Suppression.suppressed?(ADDRESS)
    assert_equal lifted_at, record.reload.lifted_at

    RecordingStudioNotificationsEmail::Suppression.lift!(ADDRESS, at: 1.hour.from_now)
    assert_equal lifted_at, record.reload.lifted_at

    RecordingStudioNotificationsEmail::Suppression.suppress!(
      address: ADDRESS,
      reason: "complaint",
      provider: "Email"
    )
    assert RecordingStudioNotificationsEmail::Suppression.suppressed?(ADDRESS)
    assert_equal "complaint", record.reload.reason
    assert_equal "email", record.provider
    assert_nil record.lifted_at
  end

  test "complaint suppression persists when the delivery mutator is missing" do
    assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
      RecordingStudioNotificationsEmail.mark_complained!(
        reference: @reference,
        provider: "mailgun"
      )
    end

    @delivery.reload
    assert_equal @original_status, @delivery.status
    record = RecordingStudioNotificationsEmail::Suppression.find_by!(address: ADDRESS)
    assert_equal "complaint", record.reason
    assert_equal "mailgun", record.provider
  end

  test "a suppressed address is refused before delivery" do
    RecordingStudioNotificationsEmail::Suppression.suppress!(
      address: ADDRESS,
      reason: "bounce",
      provider: "email"
    )
    delivered = ActionMailer::Base.deliveries.size

    error = assert_raises(RecordingStudioNotificationsEmail::SuppressedRecipientError) do
      RecordingStudioNotificationsEmail.adapter.deliver(
        notification: @notification,
        delivery: @delivery
      )
    end

    assert_equal "email recipient is suppressed", error.message
    assert_equal delivered, ActionMailer::Base.deliveries.size
  end
end
