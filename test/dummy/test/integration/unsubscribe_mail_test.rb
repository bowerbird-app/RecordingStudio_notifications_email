# frozen_string_literal: true

require "test_helper"

class UnsubscribeMailTest < ActiveSupport::TestCase
  test "individual mail carries the notifications unsubscribe headers and link" do
    user = User.create!(
      email: "unsubscribe-mail@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    notification = RecordingStudioNotifications.notify(
      notification_type: :system_announcement,
      recipient: user,
      actor: user,
      title: "Unsubscribe target",
      body: "Fake address only.",
      channels: [:email],
      idempotency_key: "unsubscribe-mail/#{SecureRandom.uuid}"
    )
    delivery = RecordingStudioNotifications::Delivery.find_by!(
      notification_id: notification.id,
      channel: "email"
    )

    RecordingStudioNotificationsEmail.adapter.deliver(notification: notification, delivery: delivery)

    mail = ActionMailer::Base.deliveries.last
    header = mail["List-Unsubscribe"].value
    assert_includes header, "http://example.com/recording_studio_notifications/unsubscribe/system_announcement/email?token="
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].value
    assert_includes mail.html_part.body.to_s, "Unsubscribe"
    assert_includes mail.text_part.body.to_s, "Unsubscribe: http://example.com/"
  end
end
