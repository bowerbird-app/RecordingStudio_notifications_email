# frozen_string_literal: true

require "test_helper"

class PageCommentMailTest < ActiveSupport::TestCase
  test "page comment mail renders the channel_options template" do
    user = User.create!(
      email: "page-comment-mail@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    workspace = Workspace.create!(name: "Comment Mail Workspace")
    root = RecordingStudio.root_recording_for(workspace)
    notification = RecordingStudioNotifications.notify(
      notification_type: :page_comment,
      recipient: user,
      actor: user,
      root_recording: root,
      title: "New comment on Launch plan",
      body: "Looks good.",
      channels: [:email],
      idempotency_key: "page-comment-mail/#{SecureRandom.uuid}"
    )
    delivery = RecordingStudioNotifications::Delivery.find_by!(
      notification_id: notification.id,
      channel: "email"
    )

    RecordingStudioNotificationsEmail.adapter.deliver(notification: notification, delivery: delivery)

    mail = ActionMailer::Base.deliveries.last
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    assert_includes html, "Open page"
    assert_includes html, "Notification type"
    assert_includes text, "Open page"
    refute_includes html, "View notification"
  end
end
