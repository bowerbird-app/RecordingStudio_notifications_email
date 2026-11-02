# frozen_string_literal: true

RecordingStudioNotificationsEmail.configure do |config|
  # Required. Prefer Rails credentials in production.
  config.from = Rails.application.credentials.dig(:notifications, :from_email)

  # Optional model-specific resolution. By default, recipients must respond to
  # `email`.
  # config.recipients.register(User) { |user| user.notification_email }

  # Optional template paths belong on the notification type:
  # channel_options: { email: { individual_mailer:, rollup_mailer: } }
  # Provide matching .html.erb and .text.erb templates under app/views.
end
