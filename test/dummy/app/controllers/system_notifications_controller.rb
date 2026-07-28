# frozen_string_literal: true

class SystemNotificationsController < ApplicationController
  def new
    @default_message = "System maintenance window tonight at 10 PM UTC."
  end

  def create
    title = system_notification_params.fetch(:title)
    body = system_notification_params.fetch(:body)

    recipients = User.order(:email)
    recipients.each do |recipient|
      RecordingStudioNotifications.notify(
        notification_type: :system_announcement,
        recipient: recipient,
        actor: current_user,
        title: title,
        body: body,
        metadata: {
          source: "system_notification",
          created_by_id: current_user.id
        },
        channels: [:in_app],
        idempotency_key: "system-announcement/#{announcement_token}/#{recipient.id}"
      )
    end

    redirect_to new_system_notification_path, notice: "System notification sent to #{recipients.count} users."
  rescue KeyError => e
    redirect_to new_system_notification_path, alert: "Missing field: #{e.message}"
  end

  private

  def system_notification_params
    params.require(:system_notification).permit(:title, :body)
  end

  def announcement_token
    @announcement_token ||= SecureRandom.uuid
  end
end
