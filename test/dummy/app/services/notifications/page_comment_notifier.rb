# frozen_string_literal: true

module Notifications
  class PageCommentNotifier
    class << self
      def call(event_payload)
        new(event_payload).call
      end
    end

    def initialize(event_payload)
      @event_payload = event_payload.with_indifferent_access
    end

    def call
      return unless comment_created_event?

      comment_recording = RecordingStudio::Recording.find_by(id: @event_payload[:recording_id])
      return unless comment_recording

      page_recording = page_recording_for(comment_recording)
      return unless page_recording

      page = page_recording.recordable
      root_recording = page_recording.root_recording
      return unless page.is_a?(Page) && root_recording

      comment = comment_recording.recordable
      commenter_id = commenter_id_for(comment)
      recipients_for(root_recording).each do |recipient|
        next if commenter_id.present? && recipient.id.to_s == commenter_id

        notify_page_comment(
          recipient: recipient,
          actor: actor,
          root_recording: root_recording,
          page_recording: page_recording,
          page: page,
          comment: comment
        )
      end
    end

    private

    def comment_created_event?
      @event_payload[:action].to_s == "created" &&
        @event_payload[:recordable_type].to_s == "RecordingStudioCommentable::Comment"
    end

    def page_recording_for(comment_recording)
      current = comment_recording.parent_recording
      while current&.recordable_type == "RecordingStudioCommentable::Comment"
        current = current.parent_recording
      end

      return current if current&.recordable_type == "Page"

      nil
    end

    def actor
      actor_type = @event_payload[:actor_type].to_s
      actor_id = @event_payload[:actor_id].to_s
      return if actor_type.blank? || actor_id.blank?

      actor_type.safe_constantize&.find_by(id: actor_id)
    end

    def recipients_for(root_recording)
      User.order(:email).select do |user|
        RecordingStudioAccessible.authorized?(actor: user, recording: root_recording, role: :view)
      end
    end

    def comments_path_for(page_recording)
      Rails.application.routes.url_helpers.all_recording_comments_path(page_recording)
    rescue StandardError
      nil
    end

    def notification_channels
      return [:in_app, :email] if Rails.env.development?

      [:in_app]
    end

    def commenter_id_for(comment)
      return actor.id.to_s if actor&.respond_to?(:id) && actor.id.present?

      author = comment.respond_to?(:author) ? comment.author : nil
      return author.id.to_s if author&.respond_to?(:id) && author.id.present?

      nil
    end

    def notify_page_comment(recipient:, actor:, root_recording:, page_recording:, page:, comment:)
      RecordingStudioNotifications.notify(
        notification_type: :page_comment,
        recipient: recipient,
        actor: actor,
        root_recording: root_recording,
        recording: page_recording,
        title: "New comment on #{page.title.presence || 'a page'}",
        body: comment&.body.to_s,
        url: comments_path_for(page_recording),
        metadata: {
          source: "page_comment",
          page_id: page.id,
          comment_id: comment&.id,
          root_recording_id: root_recording.id,
          event_id: @event_payload[:event_id]
        },
        channels: notification_channels,
        idempotency_key: "page-comment/#{@event_payload[:event_id]}/#{recipient.id}"
      )
    rescue StandardError => e
      # Keep comment creation resilient even if notification delivery setup is misconfigured.
      Rails.logger&.warn("[PageCommentNotifier] notification skipped: #{e.class} #{e.message}")
      nil
    end
  end
end