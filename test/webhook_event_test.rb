# frozen_string_literal: true

require "test_helper"

class WebhookEventTest < Minitest::Test
  def test_normalizes_input
    event = RecordingStudioNotificationsEmail::WebhookEvent.new(
      provider: " Postmark ",
      event_type: "opened",
      reference: "signed-reference",
      occurred_at: Time.utc(2026, 7, 22, 0, 0, 0),
      external_event_id: " event-1 ",
      external_message_id: " message-1 ",
      metadata: { "stream" => "outbound" }
    )

    assert_equal :postmark, event.provider
    assert_equal :opened, event.event_type
    assert_equal "signed-reference", event.reference
    assert_equal "event-1", event.external_event_id
    assert_equal "message-1", event.external_message_id
    assert_equal({ "stream" => "outbound" }, event.metadata)
  end

  def test_requires_provider
    assert_raises(RecordingStudioNotificationsEmail::InvalidWebhookPayloadError) do
      RecordingStudioNotificationsEmail::WebhookEvent.new(
        provider: "",
        event_type: :opened,
        reference: "signed-reference"
      )
    end
  end

  def test_requires_reference
    assert_raises(RecordingStudioNotificationsEmail::InvalidWebhookPayloadError) do
      RecordingStudioNotificationsEmail::WebhookEvent.new(
        provider: :postmark,
        event_type: :opened,
        reference: nil
      )
    end
  end

  def test_rejects_unknown_event_type
    assert_raises(RecordingStudioNotificationsEmail::UnsupportedWebhookEventError) do
      RecordingStudioNotificationsEmail::WebhookEvent.new(
        provider: :postmark,
        event_type: :processed,
        reference: "signed-reference"
      )
    end
  end

  def test_rejects_non_hash_metadata
    assert_raises(RecordingStudioNotificationsEmail::InvalidWebhookPayloadError) do
      RecordingStudioNotificationsEmail::WebhookEvent.new(
        provider: :postmark,
        event_type: :opened,
        reference: "signed-reference",
        metadata: "not-a-hash"
      )
    end
  end
end