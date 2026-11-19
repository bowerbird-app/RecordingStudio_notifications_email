# frozen_string_literal: true

require "test_helper"
require "action_mailbox/test_case"

class ReplyByEmailTest < ActionMailbox::TestCase
  UUID = "11111111-1111-4111-8111-111111111111"
  Target = Struct.new(:notification, :recipient, keyword_init: true)

  setup do
    @configuration = RecordingStudioNotificationsEmail.configuration
    @previous = {
      reply_domain: @configuration.reply_domain,
      message_id_domain: @configuration.message_id_domain,
      require_inbound_authentication: @configuration.require_inbound_authentication,
      reply_max_body_bytes: @configuration.reply_max_body_bytes,
      reply_max_attachment_bytes: @configuration.reply_max_attachment_bytes,
      reply_max_attachments: @configuration.reply_max_attachments
    }
    @configuration.reply_domain = "reply.example.test"
    @configuration.message_id_domain = "mail.example.test"
    @configuration.require_inbound_authentication = true
    @configuration.reply_max_body_bytes = 64 * 1024
    @configuration.reply_max_attachment_bytes = 10 * 1024 * 1024
    @configuration.reply_max_attachments = 10
    @recipient = Struct.new(:email).new("person@example.test")
    @notification = Object.new
    @target = Target.new(notification: @notification, recipient: @recipient)
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    @previous.each { |key, value| @configuration.public_send("#{key}=", value) }
  end

  test "a reply is processed and does not send mail" do
    seen = nil
    inbound = receive_reply(mail_source) do |**kwargs|
      seen = kwargs
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert inbound.delivered?
    refute inbound.bounced?
    assert_empty ActionMailer::Base.deliveries
    assert_equal "Thanks for the note", seen.fetch(:body)
    assert_equal :email, seen.fetch(:channel)
    assert_equal "reply-1@example.test", seen.fetch(:idempotency_key)
    assert_equal [], seen.fetch(:attachments)
  end

  test "reply results map to processed or rejected without a bounce" do
    ok = receive_reply(mail_source("ok@example.test")) { RecordingStudioNotifications::ReplyResult.ok }
    duplicate = receive_reply(mail_source("duplicate@example.test")) { RecordingStudioNotifications::ReplyResult.duplicate }
    rejected = receive_reply(mail_source("rejected@example.test")) { RecordingStudioNotifications::ReplyResult.rejected(:closed) }
    failed = receive_reply(mail_source("failed@example.test")) { RecordingStudioNotifications::ReplyResult.failed(:handler_error) }

    assert ok.delivered?
    assert duplicate.delivered?
    assert rejected.delivered?
    assert failed.delivered?
    [ok, duplicate, rejected, failed].each { |inbound| refute inbound.bounced? }
    assert_empty ActionMailer::Base.deliveries
  end

  test "the same message id is processed again as a duplicate" do
    keys = []
    handler = lambda do |**kwargs|
      keys << kwargs.fetch(:idempotency_key)
      keys.one? ? RecordingStudioNotifications::ReplyResult.ok : RecordingStudioNotifications::ReplyResult.duplicate
    end

    first = receive_reply(mail_source("same@example.test", body: "First note"), handler: handler)
    second = receive_reply(mail_source("same@example.test", body: "Second note"), handler: handler)

    assert first.delivered?
    assert second.delivered?
    refute second.bounced?
    assert_equal ["same@example.test", "same@example.test"], keys
  end

  test "a spoofed from and a failed authentication check are ignored" do
    spoofed = receive_reply(mail_source("spoof@example.test", from: "other@example.test")) { flunk "handler" }
    unauthenticated = receive_reply(
      mail_source("auth@example.test", authentication: "example.test; spf=fail; dmarc=fail")
    ) { flunk "handler" }

    assert spoofed.delivered?
    assert unauthenticated.delivered?
    refute spoofed.bounced?
    refute unauthenticated.bounced?
  end

  test "auto replies and bounces are ignored" do
    auto = receive_reply(mail_source("auto@example.test", headers: { "Auto-Submitted" => "auto-replied" })) { flunk "handler" }
    bounced = receive_reply(mail_source("bounce@example.test", headers: { "Return-Path" => "<>" })) { flunk "handler" }

    assert auto.delivered?
    assert bounced.delivered?
    refute auto.bounced?
    refute bounced.bounced?
  end

  test "quoted history is stripped before the reply is filed" do
    body = <<~TEXT
      Thanks for the note

      On Tue, Nov 18, 2026 at 1:00 PM Someone <other@example.test> wrote:
      > previous message
    TEXT
    seen = nil
    receive_reply(mail_source("quote@example.test", body: body)) do |**kwargs|
      seen = kwargs.fetch(:body)
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert_equal "Thanks for the note", seen
    refute_includes seen, "other@example.test"
  end

  test "oversized replies are ignored" do
    @configuration.reply_max_body_bytes = 5
    inbound = receive_reply(mail_source("large@example.test", body: "too long")) { flunk "handler" }

    assert inbound.delivered?
    refute inbound.bounced?
  end

  test "an attachment becomes an active storage blob" do
    mail = Mail.new
    mail.from = "person@example.test"
    mail.to = reply_address
    mail.subject = "Re: notice"
    mail.message_id = "<file@example.test>"
    mail.header["Authentication-Results"] = "example.test; spf=pass"
    mail.body = "See the file"
    mail.add_file(filename: "note.txt", content: "hello")
    seen = nil

    receive_reply(mail.to_s) do |**kwargs|
      seen = kwargs.fetch(:attachments)
      RecordingStudioNotifications::ReplyResult.ok
    end

    assert_equal 1, seen.size
    assert_instance_of ActiveStorage::Blob, seen.first
    assert_equal "note.txt", seen.first.filename.to_s
    assert_equal "hello", seen.first.download
  end

  test "token round trip tamper expiry and case folding" do
    address = RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    local = address.split("@").first

    assert_operator local.length, :<=, 64
    assert_equal UUID, RecordingStudioNotificationsEmail::ReplyAddress.verify(address.upcase, configuration: @configuration)

    code = local.split("+", 2).last
    code[0] = code[0] == "a" ? "b" : "a"
    assert_nil RecordingStudioNotificationsEmail::ReplyAddress.verify("reply+#{code}@reply.example.test", configuration: @configuration)

    issued_at = Time.utc(2026, 1, 1, 0, 0, 0)
    expired = Time.stub(:now, issued_at) do
      RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    end
    assert_nil Time.stub(:now, issued_at + 30.days + 1) {
      RecordingStudioNotificationsEmail::ReplyAddress.verify(expired, configuration: @configuration)
    }
  end

  private

  def receive_reply(source, handler: nil, &block)
    callback = handler || lambda do |**kwargs|
      invoke_handler(block, **kwargs)
    end
    inbound = nil
    with_notifications(callback) do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        inbound = receive_inbound_email_from_source(source)
      end
    end
    inbound
  end

  def invoke_handler(block, **kwargs)
    flunk "handler should not run" unless block
    return block.call unless keyword_block?(block)

    block.call(**kwargs)
  end

  def keyword_block?(block)
    block.parameters.any? { |kind, _name| %i[key keyreq keyrest].include?(kind) }
  end

  def with_notifications(handler)
    reply_target = ->(delivery_id:, channel:) { @target if delivery_id == UUID && channel == :email }
    RecordingStudioNotifications.stub(:reply_target, reply_target) do
      RecordingStudioNotifications.stub(:handle_reply, handler) { yield }
    end
  end

  def mail_source(message_id = "reply-1@example.test", from: "person@example.test", body: "Thanks for the note",
                  authentication: "example.test; spf=pass", headers: {})
    mail = Mail.new
    mail.from = from
    mail.to = reply_address
    mail.subject = "Re: notice"
    mail.body = body
    mail.message_id = "<#{message_id}>"
    mail.header["Authentication-Results"] = authentication if authentication
    headers.each { |name, value| mail.header[name] = value }
    mail.to_s
  end

  def reply_address
    RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
  end
end
