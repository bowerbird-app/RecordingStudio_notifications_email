# frozen_string_literal: true

require "test_helper"
require "mail"
require_relative "reply_key"

class ParseInboundReplyTest < Minitest::Test
  include ReplyKey

  UUID = "11111111-1111-4111-8111-111111111111"
  Target = Struct.new(:notification, :recipient, keyword_init: true)
  Recipient = Struct.new(:email, keyword_init: true)

  def setup
    @configuration = RecordingStudioNotificationsEmail::Configuration.new
    @configuration.reply_domain = "reply.example.test"
    @configuration.reply_address_expires_in = 30.days
    @configuration.require_inbound_authentication = true
    @configuration.inbound_authserv_ids = ["mx.example.test"]
    @recipient = Recipient.new(email: "person@example.test")
    @notification = Object.new
    @target = Target.new(notification: @notification, recipient: @recipient)
    @logs = []
  end

  def run
    with_reply_key("e" * 64) { super }
  end

  def test_a_matching_reply_is_processed
    seen = nil
    disposition = parse(mail_for) do |kwargs|
      seen = kwargs
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert disposition.processed?
    assert_nil disposition.reason
    assert_equal @notification, seen.fetch(:notification)
    assert_equal @recipient, seen.fetch(:recipient)
    assert_equal "Thanks for the note", seen.fetch(:body)
    assert_equal [], seen.fetch(:attachments)
    assert_equal :email, seen.fetch(:channel)
    assert_equal "reply-1@example.test", seen.fetch(:idempotency_key)
    assert_equal UUID, @seen_delivery_id
    assert_equal :email, @seen_channel
    assert_includes @logs, "recording_studio_notifications_email reply processed"
    refute_includes @logs.join, "person@example.test"
    refute_includes @logs.join, "Thanks"
  end

  def test_each_reply_result_maps_to_processed_or_rejected
    assert_disposition(:ok, nil, :processed, nil)
    assert_disposition(:duplicate, nil, :processed, :duplicate)
    assert_disposition(:rejected, :closed, :rejected, :closed)
    assert_disposition(:failed, :handler_error, :rejected, :handler_error)
  end

  def test_duplicate_message_id_is_processed
    first = nil
    second = nil
    keys = []
    handler = lambda do |**kwargs|
      keys << kwargs.fetch(:idempotency_key)
      keys.one? ? RecordingStudioNotifications::ReplyResult.ok : RecordingStudioNotifications::ReplyResult.duplicate
    end

    with_notifications(handler) do
      first = call_parser(mail_for(message_id: "<same@example.test>", body: "First note"))
      second = call_parser(mail_for(message_id: "<same@example.test>", body: "Second note"))
    end

    assert first.processed?
    assert_nil first.reason
    assert second.processed?
    assert_equal :duplicate, second.reason
    assert_equal ["same@example.test", "same@example.test"], keys
  end

  def test_spoofed_from_is_rejected
    disposition = parse(mail_for(from: "other@example.test")) { flunk "handler should not run" }

    assert disposition.rejected?
    assert_equal :from_mismatch, disposition.reason
    refute_includes @logs.join, "other@example.test"
    refute_includes @logs.join, "person@example.test"
  end

  def test_from_match_is_case_insensitive
    @recipient = Recipient.new(email: "Person@Example.TEST")
    @target = Target.new(notification: @notification, recipient: @recipient)
    disposition = parse(mail_for(from: "person@example.test")) { RecordingStudioNotifications::ReplyResult.ok }

    assert disposition.processed?
  end

  def test_trusted_dmarc_pass_is_required
    forged_and_failed = parse(mail_for(authentication: [
                                         "evil.test; dmarc=pass",
                                         "mx.example.test; dmarc=fail"
                                       ])) { flunk "handler" }
    assert_equal :authentication_failed, forged_and_failed.reason

    forged = parse(mail_for(authentication: "evil.test; dmarc=pass")) { flunk "handler" }
    assert_equal :authentication_failed, forged.reason

    spf_only = parse(mail_for(authentication: "mx.example.test; spf=pass; dmarc=fail")) { flunk "handler" }
    assert_equal :authentication_failed, spf_only.reason

    missing = parse(mail_for(authentication: nil)) { flunk "handler" }
    assert_equal :authentication_failed, missing.reason

    @configuration.inbound_authserv_ids = []
    unconfigured = parse(mail_for(authentication: "mx.example.test; dmarc=pass")) { flunk "handler" }
    assert_equal :authentication_failed, unconfigured.reason
    @configuration.inbound_authserv_ids = ["mx.example.test"]

    accepted = parse(mail_for(authentication: "mx.example.test; spf=fail; dmarc=pass")) do
      RecordingStudioNotifications::ReplyResult.ok
    end
    assert accepted.processed?
  end

  def test_every_authentication_results_field_is_checked
    rejected = parse(mail_for(authentication: [
                                "mx.example.test; dmarc=fail",
                                "evil.test; dmarc=pass"
                              ])) { flunk "handler" }
    assert_equal :authentication_failed, rejected.reason

    accepted = parse(mail_for(authentication: [
                                "evil.test; dmarc=pass",
                                "MX.Example.TEST; spf=fail; dmarc=pass"
                              ])) do
      RecordingStudioNotifications::ReplyResult.ok
    end
    assert accepted.processed?
  end

  def test_authentication_can_be_turned_off
    @configuration.require_inbound_authentication = false
    disposition = parse(mail_for(authentication: nil)) { RecordingStudioNotifications::ReplyResult.ok }

    assert disposition.processed?
  end

  def test_auto_replies_and_bounces_are_dropped
    {
      { "Auto-Submitted" => "auto-replied" } => :auto_reply,
      { "Precedence" => "bulk" } => :auto_reply,
      { "X-Autoreply" => "yes" } => :auto_reply,
      { "Return-Path" => "<>" } => :bounce,
      { "Return-Path" => "mailer-daemon@example.test" } => :bounce
    }.each do |headers, reason|
      disposition = parse(mail_for(headers: headers)) { flunk "handler should not run" }
      assert_equal reason, disposition.reason
    end

    human = parse(mail_for(headers: { "Auto-Submitted" => "no" })) do
      RecordingStudioNotifications::ReplyResult.ok
    end
    assert human.processed?

    report = mail_for
    report.content_type = "multipart/report; report-type=delivery-status"
    assert_equal :bounce, parse(report) { flunk "handler" }.reason
  end

  def test_quoted_history_and_signatures_are_stripped
    body = <<~TEXT
      Thanks for the note

      On Tue, Nov 18, 2026 at 1:00 PM Someone <other@example.test> wrote:
      > previous message
    TEXT
    seen = nil
    disposition = parse(mail_for(body: body)) do |kwargs|
      seen = kwargs.fetch(:body)
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert disposition.processed?
    assert_equal "Thanks for the note", seen
    refute_includes seen, "previous"
    refute_includes seen, "other@example.test"
  end

  def test_plain_text_wins_over_html_and_html_falls_back_to_text
    mail = mail_for(body: nil)
    mail.text_part = text_part("Plain thanks")
    mail.html_part = html_part("<p>HTML thanks</p>")
    plain = nil
    parse(mail) do |kwargs|
      plain = kwargs.fetch(:body)
      RecordingStudioNotifications::ReplyResult.ok
    end
    assert_equal "Plain thanks", plain

    html_mail = mail_for(body: nil)
    html_mail.html_part = html_part("<p>HTML thanks</p><blockquote>quoted secret</blockquote>")
    html_body = nil
    parse(html_mail) do |kwargs|
      html_body = kwargs.fetch(:body)
      RecordingStudioNotifications::ReplyResult.ok
    end
    assert_includes html_body, "HTML thanks"
    refute_includes html_body, "quoted secret"
  end

  def test_signatures_are_removed
    body = "Thanks for the note\n\n-- \nPat\nperson@example.test\n"
    seen = nil
    parse(mail_for(body: body)) do |kwargs|
      seen = kwargs.fetch(:body)
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert_equal "Thanks for the note", seen
    refute_includes seen, "person@example.test"
  end

  def test_outlook_quoting_keeps_utf8_text
    body = "éé thanks\nFrom: Pat <person@example.test>\nSent: Monday\nhidden"
    seen = nil
    parse(mail_for(body: body)) do |kwargs|
      seen = kwargs.fetch(:body)
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert_equal "éé thanks", seen
    assert seen.valid_encoding?
    refute_includes seen, "hidden"
    refute_includes seen, "person@example.test"
  end

  def test_body_and_attachment_limits_reject_before_the_handler
    @configuration.reply_max_body_bytes = 5
    assert_equal :body_too_large, parse(mail_for(body: "too long")) { flunk "handler" }.reason

    @configuration.reply_max_body_bytes = 64 * 1024
    @configuration.reply_max_attachments = 1
    crowded = mail_for
    crowded.add_file(filename: "one.txt", content: "a")
    crowded.add_file(filename: "two.txt", content: "b")
    assert_equal :too_many_attachments, parse(crowded) { flunk "handler" }.reason

    @configuration.reply_max_attachments = 10
    @configuration.reply_max_attachment_bytes = 4
    large = mail_for
    large.add_file(filename: "note.txt", content: "hello")
    assert_equal :attachment_too_large, parse(large) { flunk "handler" }.reason
  end

  def test_unknown_delivery_invalid_token_and_missing_message_id_are_rejected
    assert_equal :unknown_delivery, parse(mail_for, target: nil) { flunk "handler" }.reason

    tampered = mail_for
    tampered.to = "reply+aaaa@reply.example.test"
    assert_equal :invalid_token, parse(tampered) { flunk "handler" }.reason

    missing = mail_for
    missing.message_id = nil
    assert_equal :missing_message_id, parse(missing) { RecordingStudioNotifications::ReplyResult.ok }.reason
  end

  def test_empty_body_is_rejected
    assert_equal :empty_body, parse(mail_for(body: "   ")) { flunk "handler" }.reason
  end

  def test_upcased_reply_address_is_accepted
    address = RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    mail = mail_for
    mail.to = address.upcase
    disposition = parse(mail) { RecordingStudioNotifications::ReplyResult.ok }

    assert disposition.processed?
  end

  private

  def assert_disposition(outcome, result_reason, status, reason)
    result = reply_result(outcome, result_reason)
    disposition = parse(mail_for) { result }

    assert_equal status, disposition.status
    if reason.nil?
      assert_nil disposition.reason
    else
      assert_equal reason, disposition.reason
    end
  end

  def reply_result(outcome, reason)
    case outcome
    when :ok
      RecordingStudioNotifications::ReplyResult.ok
    when :duplicate
      RecordingStudioNotifications::ReplyResult.duplicate
    when :rejected
      RecordingStudioNotifications::ReplyResult.rejected(reason)
    when :failed
      RecordingStudioNotifications::ReplyResult.failed(reason)
    end
  end

  def parse(mail, target: @target, &block)
    handler = lambda do |**kwargs|
      flunk "handler should not run" unless block

      block.arity.zero? ? block.call : block.call(**kwargs)
    end
    with_notifications(handler, target: target) { call_parser(mail) }
  end

  def call_parser(mail)
    result = with_logger do
      RecordingStudioNotificationsEmail::Services::ParseInboundReply.call(mail: mail, configuration: @configuration)
    end
    assert result.success?
    result.value
  end

  def with_notifications(handler, target: @target, &)
    reply_target = lambda do |delivery_id:, channel:|
      @seen_delivery_id = delivery_id
      @seen_channel = channel
      target
    end
    RecordingStudioNotifications.stub(:reply_target, reply_target) do
      RecordingStudioNotifications.stub(:handle_reply, handler, &)
    end
  end

  def with_logger(&)
    logs = @logs
    logger = Object.new
    logger.define_singleton_method(:info) { |line| logs << line }
    logger.define_singleton_method(:error) { |line| logs << line }
    Rails.stub(:logger, logger, &)
  end

  def mail_for(from: "person@example.test", body: "Thanks for the note", message_id: "<reply-1@example.test>",
               authentication: "mx.example.test; dmarc=pass", headers: {})
    address = RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    mail = Mail.new
    mail.from = from
    mail.to = address
    mail.subject = "Re: notice"
    mail.body = body if body
    mail.message_id = message_id if message_id
    Array(authentication).each do |value|
      mail.header["Authentication-Results"] = value
    end
    headers.each { |name, value| mail.header[name] = value }
    mail
  end

  def text_part(body)
    Mail::Part.new { body body }
  end

  def html_part(body)
    part = Mail::Part.new
    part.content_type = "text/html; charset=UTF-8"
    part.body = body
    part
  end
end
