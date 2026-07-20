# frozen_string_literal: true

module Notifications
  class PageCreatedNotifier
    class << self
      def call(event_payload)
        new(event_payload).call
      end
    end

    def initialize(event_payload)
      @event_payload = event_payload.with_indifferent_access
    end

    def call
      return unless page_created_event?
      return unless root_recording && page

      recipients.each do |recipient|
        RecordingStudioNotifications.notify(
          notification_type: :page_created,
          recipient: recipient,
          actor: actor,
          root_recording: root_recording,
          recording: recording,
          title: "New page in #{workspace_name}",
          body: page.title.presence || "A page was created",
          metadata: {
            source: "page_created",
            page_id: page.id,
            workspace_id: workspace&.id,
            root_recording_id: root_recording.id,
            event_id: @event_payload[:event_id]
          },
          channels: notification_channels,
          idempotency_key: "page-created/#{@event_payload[:event_id]}/#{recipient.id}"
        )
      end
    end

    private

    def page_created_event?
      @event_payload[:action].to_s == "created" &&
        @event_payload[:recordable_type].to_s == "Page"
    end

    def page
      @page ||= Page.find_by(id: @event_payload[:recordable_id])
    end

    def recording
      @recording ||= RecordingStudio::Recording.find_by(id: @event_payload[:recording_id])
    end

    def root_recording
      @root_recording ||= RecordingStudio::Recording.find_by(id: @event_payload[:root_recording_id])
    end

    def workspace
      @workspace ||= begin
        return unless root_recording
        return root_recording.recordable if root_recording.recordable.is_a?(Workspace)

        root_recording.recordable if root_recording.recordable_type == "Workspace"
      end
    end

    def workspace_name
      workspace&.name.presence || "a workspace"
    end

    def actor
      actor_type = @event_payload[:actor_type].to_s
      actor_id = @event_payload[:actor_id].to_s
      return if actor_type.blank? || actor_id.blank?

      actor_type.safe_constantize&.find_by(id: actor_id)
    end

    def recipients
      @recipients ||= User.order(:email).select do |user|
        RecordingStudioAccessible.authorized?(actor: user, recording: root_recording, role: :view)
      end
    end

    def notification_channels
      return [:in_app, :email] if Rails.env.development?

      [:in_app]
    end
  end
end
