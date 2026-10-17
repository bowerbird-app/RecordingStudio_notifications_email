# frozen_string_literal: true

require "test_helper"
require File.expand_path("../app/mailers/recording_studio_notifications_email/notification_mailer", __dir__)

class NotificationMailerTest < Minitest::Test
  Notification = Struct.new(:id, :notification_type, :title, :body, :url, keyword_init: true)

  def setup
    RecordingStudioNotificationsEmail::NotificationMailer.prepend_view_path(
      RecordingStudioNotificationsEmail::Engine.root.join("app/views")
    )
  end

  def test_fallback_templates_render_multipart_message_and_correlation_header
    event = RecordingStudioNotificationsEmail::Event.new(
      Notification.new(
        id: "notification-1",
        notification_type: :generic,
        title: "Account notice",
        body: "A useful update",
        url: "/notifications/1"
      )
    )

    message = RecordingStudioNotificationsEmail::NotificationMailer.with(
      event: event,
      to: "person@example.test",
      from: "notifications@example.test",
      template_path: RecordingStudioNotificationsEmail::Configuration::DEFAULT_TEMPLATE,
      correlation_reference: "signed-reference"
    ).notification

    assert_equal ["person@example.test"], message.to
    assert_equal ["notifications@example.test"], message.from
    assert_equal "Account notice", message.subject
    assert_equal "signed-reference", message[RecordingStudioNotificationsEmail::DeliveryToken::HEADER].value
    assert_includes message.html_part.body.to_s, "A useful update"
    assert_includes message.text_part.body.to_s, "A useful update"
  end

  def test_fallback_templates_escape_untrusted_notification_content
    event = RecordingStudioNotificationsEmail::Event.new(
      Notification.new(
        id: "notification-1",
        notification_type: :generic,
        title: "<script>alert(1)</script>",
        body: "<img src=x onerror=alert(1)>"
      )
    )

    message = RecordingStudioNotificationsEmail::NotificationMailer.with(
      event: event,
      to: "person@example.test",
      from: "notifications@example.test",
      template_path: RecordingStudioNotificationsEmail::Configuration::DEFAULT_TEMPLATE,
      correlation_reference: "signed-reference"
    ).notification

    refute_includes message.html_part.body.to_s, "<script>"
    refute_includes message.html_part.body.to_s, "<img"
  end

  def test_rollup_fallback_renders_each_event_in_html_and_text
    events = [
      RecordingStudioNotificationsEmail::Event.new(
        Notification.new(id: "notification-1", notification_type: :generic, title: "First")
      ),
      RecordingStudioNotificationsEmail::Event.new(
        Notification.new(id: "notification-2", notification_type: :generic, title: "Second")
      )
    ]

    message = RecordingStudioNotificationsEmail::NotificationMailer.with(
      events: events,
      to: "person@example.test",
      from: "notifications@example.test",
      template_path: RecordingStudioNotificationsEmail::Configuration::DEFAULT_ROLLUP_TEMPLATE,
      correlation_reference: "signed-reference",
      cadence: :weekly,
      period_starts_at: Time.now - 1.week,
      period_ends_at: Time.now
    ).rollup

    assert_equal "2 notifications", message.subject
    assert_includes message.html_part.body.to_s, "First"
    assert_includes message.html_part.body.to_s, "Second"
    assert_includes message.text_part.body.to_s, "First"
    assert_includes message.text_part.body.to_s, "Second"
  end

  def test_messages_include_list_unsubscribe_headers_and_a_link
    recipient = Object.new
    source = Struct.new(:id, :notification_type, :title, :body, :url, :recipient, keyword_init: true)
    event = RecordingStudioNotificationsEmail::Event.new(
      source.new(
        id: "notification-1",
        notification_type: :generic,
        title: "Account notice",
        body: "A useful update",
        recipient: recipient
      )
    )
    headers = {
      "List-Unsubscribe" => "<http://example.test/unsub>",
      "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
    }

    message = with_unsubscribe_helpers(headers) do
      RecordingStudioNotificationsEmail::NotificationMailer.with(
        event: event,
        to: "person@example.test",
        from: "notifications@example.test",
        template_path: RecordingStudioNotificationsEmail::Configuration::DEFAULT_TEMPLATE,
        correlation_reference: "signed-reference"
      ).notification.message
    end

    assert_equal "<http://example.test/unsub>", message["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", message["List-Unsubscribe-Post"].value
    assert_includes message.html_part.body.to_s, "http://example.test/unsub"
    assert_includes message.text_part.body.to_s, "Unsubscribe: http://example.test/unsub"

    rollup = with_unsubscribe_helpers(headers) do
      RecordingStudioNotificationsEmail::NotificationMailer.with(
        events: [event],
        to: "person@example.test",
        from: "notifications@example.test",
        template_path: RecordingStudioNotificationsEmail::Configuration::DEFAULT_ROLLUP_TEMPLATE,
        correlation_reference: "signed-reference",
        cadence: :weekly,
        period_starts_at: Time.now - 1.week,
        period_ends_at: Time.now
      ).rollup.message
    end

    assert_equal "<http://example.test/unsub>", rollup["List-Unsubscribe"].value
    assert_includes rollup.html_part.body.to_s, "http://example.test/unsub"
    assert_includes rollup.text_part.body.to_s, "Unsubscribe: http://example.test/unsub"
  end

  private

  def with_unsubscribe_helpers(headers, &block)
    RecordingStudioNotifications.stub(:list_unsubscribe_headers, headers) do
      RecordingStudioNotifications.stub(:unsubscribe_url, "http://example.test/unsub", &block)
    end
  end
end
