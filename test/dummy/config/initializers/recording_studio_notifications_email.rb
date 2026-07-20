# frozen_string_literal: true

RecordingStudioNotificationsEmail.configure do |config|
  config.from = "notifications@example.test"
  config.templates.register(
    :page_created,
    "recording_studio_notifications_email/notification_mailer/page_created"
  )
  config.templates.register(
    :page_comment,
    "recording_studio_notifications_email/notification_mailer/page_comment"
  )
end
