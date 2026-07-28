# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  class WebhookError < StandardError; end

  class InvalidWebhookPayloadError < WebhookError; end

  class UnsupportedWebhookEventError < WebhookError; end
end
