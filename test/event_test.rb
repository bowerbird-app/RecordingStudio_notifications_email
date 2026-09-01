# frozen_string_literal: true

require "test_helper"

class EventTest < Minitest::Test
  Notification = Struct.new(
    :id, :notification_type, :title, :body, :url, :metadata, :recipient,
    :actor, :notifiable, :recording, :root_recording, :created_at,
    keyword_init: true
  )
  Recording = Struct.new(:recordable, keyword_init: true)

  def test_normalizes_parent_notification_attributes
    notification = Notification.new(
      id: "notification-1",
      notification_type: "page_comment",
      title: "New comment",
      body: "Hello",
      metadata: { "safe" => true }
    )

    event = RecordingStudioNotificationsEmail::Event.new(notification)

    assert_equal :page_comment, event.notification_type
    assert_equal "New comment", event.title
    assert_equal "Hello", event.body
    assert_equal({ "safe" => true }, event.metadata)
    assert_predicate event.metadata, :frozen?
  end

  def test_presentation_and_root_resolution_delegate_to_recording_studio
    notifiable = Object.new
    recording = Object.new
    root = Struct.new(:id).new("root-1")
    notification = Notification.new(notifiable: notifiable, recording: recording)

    RecordingStudio.stub(:recordable_name, ->(value) { "Page" if value.equal?(notifiable) }) do
      RecordingStudio.stub(:recordable_type_label, ->(value) { "Document" if value.equal?(notifiable) }) do
        RecordingStudio.stub(:root_recording_or_self, ->(value) { root if value.equal?(recording) }) do
          RecordingStudio.stub(:root_recording_id_for, lambda(&:id)) do
            event = RecordingStudioNotificationsEmail::Event.new(notification)

            assert_equal "Page", event.recordable_name
            assert_equal "Document", event.recordable_type_label
            assert_equal root, event.root_recording
            assert_equal "root-1", event.root_recording_id
          end
        end
      end
    end
  end

  def test_missing_optional_attributes_are_safe
    event = RecordingStudioNotificationsEmail::Event.new({ notification_type: " " })

    assert_equal :generic, event.notification_type
    assert_equal "Notification", event.title
    assert_nil event.body
    assert_equal({}, event.metadata)
  end

  def test_notifiable_falls_back_to_recording_recordable
    recordable = Object.new
    notification = Notification.new(recording: Recording.new(recordable: recordable))

    event = RecordingStudioNotificationsEmail::Event.new(notification)

    assert_same recordable, event.notifiable
  end

  def test_metadata_is_deeply_read_only_and_title_cannot_inject_headers
    event = RecordingStudioNotificationsEmail::Event.new(
      {
        title: "Notice\nBcc: victim@example.test",
        metadata: { "nested" => ["value"] }
      }
    )

    assert_equal "Notice Bcc: victim@example.test", event.title
    assert_predicate event.metadata.fetch("nested"), :frozen?
    assert_predicate event.metadata.fetch("nested").first, :frozen?
  end

  def test_fallback_title_cannot_inject_headers
    notifiable = Object.new
    event = RecordingStudioNotificationsEmail::Event.new(
      { notifiable: notifiable, action: "changed\nBcc: victim" }
    )

    RecordingStudio.stub(:recordable_type_label, "Page\nCc: victim") do
      assert_equal "Page Cc: victim changed Bcc: victim", event.title
    end
  end

  def test_builtin_url_fallback_fails_closed
    event = RecordingStudioNotificationsEmail::Event.new({})

    assert event.send(:fallback_url_safe?, "/notifications/1")
    assert event.send(:fallback_url_safe?, "https://example.test/notifications/1")
    refute event.send(:fallback_url_safe?, "//evil.example/steal")
    refute event.send(:fallback_url_safe?, "javascript:alert(1)")
  end

  def test_url_rejects_backslashes_before_parent_url_safety
    skip "RecordingStudioNotifications::UrlSafety unavailable" unless defined?(RecordingStudioNotifications::UrlSafety)

    event = RecordingStudioNotificationsEmail::Event.new({ url: "/notifications\\1" })

    RecordingStudioNotifications::UrlSafety.stub(:safe?, ->(*) { flunk("expected to reject before UrlSafety") }) do
      assert_nil event.url
    end
  end

  def test_url_rejects_ascii_controls_before_fallback_url_safety
    event = RecordingStudioNotificationsEmail::Event.new({ url: "/notifications/\u0000control" })

    with_url_safety_unavailable do
      event.stub(:fallback_url_safe?, ->(*) { flunk("expected to reject before fallback") }) do
        assert_nil event.url
      end
    end
  end

  def test_title_body_and_url_use_delivery_payload_when_delivery_present
    skip "RecordingStudioNotifications.delivery_payload_for unavailable" unless delivery_payload_available?

    notification = Notification.new(
      notification_type: :otp_sign_in,
      title: "Stored title",
      body: "Stored body",
      url: "/stored"
    )
    delivery = Object.new
    payload = RecordingStudioNotifications::DeliveryPayload.new(
      title: "Your sign-in code",
      body: "123456",
      url: nil
    )

    RecordingStudioNotifications.stub(:delivery_payload_for, payload) do
      event = RecordingStudioNotificationsEmail::Event.new(notification, delivery: delivery)

      assert_equal "Your sign-in code", event.title
      assert_equal "123456", event.body
      assert_nil event.url
    end
  end

  def test_without_delivery_reads_notification_attributes
    notification = Notification.new(
      notification_type: :otp_sign_in,
      title: "Stored title",
      body: "Stored body",
      url: "/notifications/1"
    )

    event = RecordingStudioNotificationsEmail::Event.new(notification)

    assert_equal "Stored title", event.title
    assert_equal "Stored body", event.body
    assert_equal "/notifications/1", event.url
  end

  private

  def delivery_payload_available?
    defined?(RecordingStudioNotifications) &&
      RecordingStudioNotifications.respond_to?(:delivery_payload_for)
  end

  def with_url_safety_unavailable
    unless defined?(RecordingStudioNotifications::UrlSafety)
      yield
      return
    end

    original = RecordingStudioNotifications.send(:remove_const, :UrlSafety)
    yield
  ensure
    RecordingStudioNotifications.const_set(:UrlSafety, original) if defined?(original) && original
  end
end
