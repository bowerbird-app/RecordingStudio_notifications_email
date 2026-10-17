# frozen_string_literal: true

require "test_helper"

class WebhooksApplyEventTest < Minitest::Test
  Inbound = Struct.new(:provider_name, :event_type, :provider_event_id, :received_at, keyword_init: true)
  Context = Struct.new(:inbound_event, :payload, keyword_init: true)

  def teardown
    Object.send(:remove_const, :RecordingStudioWebhooks) if defined?(RecordingStudioWebhooks)
  end

  def test_register_requires_the_webhooks_engine
    error = assert_raises(RecordingStudioNotificationsEmail::ConfigurationError) do
      RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.register!(provider: "postmark")
    end

    assert_includes error.message, "recording_studio_webhooks"
  end

  def test_register_delegates_to_the_webhooks_engine
    registered = nil
    webhooks = Module.new do
      define_singleton_method(:register_action) do |name, implementation, **options|
        registered = [name, implementation, options]
      end
    end
    Object.const_set(:RecordingStudioWebhooks, webhooks)

    RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.register!(provider: "postmark")

    assert_equal "recording_studio_notifications_email.apply_event", registered[0]
    assert_equal RecordingStudioNotificationsEmail::Webhooks::ApplyEvent, registered[1]
    assert_equal "postmark", registered[2].fetch(:provider)
    assert_equal "*", registered[2].fetch(:event)
  end

  def test_call_builds_a_webhook_event_and_processes_it
    occurred_at = Time.utc(2026, 7, 22, 0, 0, 0)
    context = Context.new(
      inbound_event: Inbound.new(
        provider_name: "postmark",
        event_type: "delivered",
        provider_event_id: "evt_123",
        received_at: occurred_at
      ),
      payload: {
        "reference" => "signed-reference",
        "external_message_id" => "msg_123",
        "metadata" => { "stream" => "outbound" }
      }
    )
    seen = nil
    processor = lambda do |event:|
      seen = event
      :processed
    end

    result = RecordingStudioNotificationsEmail.stub(:process_webhook_event!, processor) do
      RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.call(context)
    end

    assert_equal :processed, result
    assert_equal :postmark, seen.provider
    assert_equal :delivered, seen.event_type
    assert_equal "signed-reference", seen.reference
    assert_equal occurred_at, seen.occurred_at
    assert_equal "evt_123", seen.external_event_id
    assert_equal "msg_123", seen.external_message_id
    assert_equal({ "stream" => "outbound" }, seen.metadata)
  end

  def test_build_event_uses_payload_time_and_message_id
    context = Context.new(
      inbound_event: Inbound.new(provider_name: "postmark", event_type: "opened", received_at: Time.utc(2020, 1, 1)),
      payload: {
        reference: "signed-reference",
        occurred_at: "2026-07-22T00:00:00Z",
        message_id: "msg_from_provider",
        metadata: "ignored"
      }
    )

    event = RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)

    assert_equal Time.iso8601("2026-07-22T00:00:00Z"), event.occurred_at
    assert_equal "msg_from_provider", event.external_message_id
    assert_equal({}, event.metadata)
  end

  def test_build_event_falls_back_to_received_at
    received_at = Time.utc(2026, 7, 22, 1, 0, 0)
    context = Context.new(
      inbound_event: Inbound.new(
        provider_name: "postmark",
        event_type: "delivered",
        received_at: received_at
      ),
      payload: { "reference" => "signed-reference" }
    )

    event = RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)

    assert_equal received_at, event.occurred_at
    assert_nil event.external_event_id
    assert_nil event.external_message_id
  end

  def test_build_event_defaults_occurred_at_to_now
    context = Context.new(
      inbound_event: Inbound.new(provider_name: "postmark", event_type: "delivered"),
      payload: { "reference" => "signed-reference" }
    )

    event = RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)

    assert_in_delta Time.current, event.occurred_at, 2
  end

  def test_build_event_normalises_bounce_type_from_the_payload
    context = Context.new(
      inbound_event: Inbound.new(provider_name: "postmark", event_type: "bounced"),
      payload: { "reference" => "signed-reference", "bounce_type" => "HardBounce" }
    )

    event = RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)

    assert_equal :hard, event.bounce_type
  end

  def test_build_event_reads_bounce_type_from_metadata
    context = Context.new(
      inbound_event: Inbound.new(provider_name: "ses", event_type: "bounced"),
      payload: {
        "reference" => "signed-reference",
        "metadata" => { "bounceType" => "Transient" }
      }
    )

    event = RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)

    assert_equal :soft, event.bounce_type
  end

  def test_build_event_prefers_camel_case_bounce_type_when_the_snake_case_value_is_blank
    context = Context.new(
      inbound_event: Inbound.new(provider_name: "ses", event_type: "bounced"),
      payload: {
        "reference" => "signed-reference",
        "bounce_type" => "  ",
        "bounceType" => "Temporary"
      }
    )

    event = RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)

    assert_equal :soft, event.bounce_type
  end

  def test_build_event_reads_a_symbol_bounce_type_from_metadata
    context = Context.new(
      inbound_event: Inbound.new(provider_name: "ses", event_type: "bounced"),
      payload: {
        "reference" => "signed-reference",
        "metadata" => { bounce_type: "permanent" }
      }
    )

    event = RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)

    assert_equal :hard, event.bounce_type
  end

  def test_build_event_treats_an_undetermined_bounce_type_as_soft
    context = Context.new(
      inbound_event: Inbound.new(provider_name: "ses", event_type: "bounced"),
      payload: { "reference" => "signed-reference", "bounceType" => "Undetermined" }
    )

    event = RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)

    assert_equal :soft, event.bounce_type
  end

  def test_missing_reference_is_rejected
    context = Context.new(
      inbound_event: Inbound.new(provider_name: "postmark", event_type: "delivered"),
      payload: {}
    )

    assert_raises(RecordingStudioNotificationsEmail::InvalidWebhookPayloadError) do
      RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.build_event(context)
    end
  end
end
