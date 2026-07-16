# frozen_string_literal: true

RecordingStudioNotificationsEmail.configure do |config|
  # Required. Prefer Rails credentials in production.
  config.from = Rails.application.credentials.dig(:notifications, :from_email)

  # Optional model-specific resolution. By default, recipients must respond to
  # `email`.
  # config.recipients.register(User) { |user| user.notification_email }

  # Optional per-notification template override. Provide matching .html.erb and
  # .text.erb templates under app/views.
  # config.templates.register(:page_comment, "notification_mailer/page_comment")
end
