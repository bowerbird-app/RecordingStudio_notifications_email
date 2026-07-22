# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"
require "cgi"

class WebhookLabTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "webhook lab page renders controls" do
    user = create_user("webhook-lab-page@example.com")
    sign_in user

    get docs_webhook_lab_path

    assert_response :success
    assert_includes unescaped_response_body, "Webhook Lab"
    assert_includes unescaped_response_body, "Create notification target"
  end

  test "create target notification shows notification and delivery ids" do
    user = create_user("webhook-lab-target@example.com")
    sign_in user

    notification, delivery = create_target_notification_for(user)

    assert_includes unescaped_response_body, notification.id
    assert_includes unescaped_response_body, delivery.id
    assert_includes unescaped_response_body, "Signed reference"
  end

  test "firing delivered event updates delivery and shows idempotency key" do
    user = create_user("webhook-lab-delivered@example.com")
    sign_in user

    _notification, delivery = create_target_notification_for(user)

    post fire_docs_webhook_lab_event_path, params: {
      event_type: "delivered",
      external_event_id: "evt-delivered-001",
      transformer_mode: "none"
    }
    follow_redirect!

    assert_response :success
    delivery.reload
    assert delivery.delivered?
    assert_includes unescaped_response_body, "\"event_type\": \"delivered\""
    assert_includes unescaped_response_body, "\"idempotency_key\": \"dummy:evt-delivered-001\""
  end

  test "replay last payload marks request as replayed" do
    user = create_user("webhook-lab-replay@example.com")
    sign_in user

    create_target_notification_for(user)

    post fire_docs_webhook_lab_event_path, params: {
      event_type: "delivered",
      external_event_id: "evt-replay-001",
      transformer_mode: "none"
    }
    follow_redirect!

    post fire_docs_webhook_lab_event_path, params: {
      repeat_last: true
    }
    follow_redirect!

    assert_response :success
    assert_includes unescaped_response_body, "\"replayed\": true"
    assert_includes unescaped_response_body, "\"idempotency_key\": \"dummy:evt-replay-001\""
  end

  test "transformer mode remaps opened to clicked" do
    user = create_user("webhook-lab-transform@example.com")
    sign_in user

    create_target_notification_for(user)

    post fire_docs_webhook_lab_event_path, params: {
      event_type: "opened",
      external_event_id: "evt-opened-001",
      transformer_mode: "opened_to_clicked"
    }
    follow_redirect!

    assert_response :success
    assert_includes unescaped_response_body, "\"transformer_mode\": \"opened_to_clicked\""

    transformed_to_clicked = unescaped_response_body.include?("\"event_type\": \"clicked\"") ||
      unescaped_response_body.include?("clicked callbacks")
    assert transformed_to_clicked,
           "expected webhook result to show clicked event handling after transformer remap"
  end

  private

  def create_user(email)
    User.find_or_create_by!(email: email) do |record|
      record.password = "Password123!"
      record.password_confirmation = "Password123!"
    end
  end

  def create_target_notification_for(user)
    post create_docs_webhook_lab_notification_path
    follow_redirect!

    assert_response :success

    notification = RecordingStudioNotifications::Notification
      .where(
        recipient_type: user.class.name,
        recipient_id: user.id,
        notification_type: "system_announcement"
      )
      .where("idempotency_key LIKE ?", "webhook-lab/#{user.id}/%")
      .order(created_at: :desc)
      .first

    assert notification, "expected webhook lab target notification to be created"

    delivery = RecordingStudioNotifications::Delivery
      .where(notification_id: notification.id, channel: :email)
      .order(created_at: :desc)
      .first

    assert delivery, "expected webhook lab email delivery to be created"

    [notification, delivery]
  end

  def unescaped_response_body
    CGI.unescapeHTML(response.body)
  end
end
