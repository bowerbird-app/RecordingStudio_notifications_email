# frozen_string_literal: true

class SystemNotificationsController < ApplicationController
  before_action :require_workspace_admin

  def new
    @default_message = "System maintenance window tonight at 10 PM UTC."
  end

  def create
    title = system_notification_params.fetch(:title)
    body = system_notification_params.fetch(:body)

    recipients = people_in_the_current_workspace
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

    redirect_to new_system_notifications_path,
                notice: "Notice sent to #{recipients.size} #{'person'.pluralize(recipients.size)} in this workspace."
  rescue KeyError => e
    redirect_to new_system_notifications_path, alert: "Missing field: #{e.message}"
  end

  private

  def system_notification_params
    params.require(:system_notification).permit(:title, :body)
  end

  def people_in_the_current_workspace
    RecordingStudioAccessible.access_recordings_for(current_root_recording).filter_map do |access_recording|
      access = access_recording.recordable
      actor = access.actor if access.respond_to?(:actor)
      actor if actor.is_a?(User)
    end.uniq
  end

  def announcement_token
    @announcement_token ||= SecureRandom.uuid
  end

  def require_workspace_admin
    recording = current_root_recording
    return if recording && RecordingStudioAccessible.authorized?(actor: current_user, recording: recording, role: :admin)

    redirect_to root_path, alert: "You don't have access to send a notice from this workspace."
  end
end
