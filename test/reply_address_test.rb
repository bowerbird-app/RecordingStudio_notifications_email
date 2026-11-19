# frozen_string_literal: true

require "test_helper"
require "open3"

class ReplyAddressTest < Minitest::Test
  UUID = "11111111-1111-4111-8111-111111111111"

  def setup
    @configuration = RecordingStudioNotificationsEmail::Configuration.new
    @configuration.message_verifier = ActiveSupport::MessageVerifier.new("c" * 64, serializer: JSON)
    @configuration.reply_domain = "reply.example.test"
    @configuration.reply_address_expires_in = 30.days
  end

  def test_round_trip_is_lowercase_base32_and_fits_the_local_part_limit
    address = RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    local = address.split("@").first

    assert_equal UUID, RecordingStudioNotificationsEmail::ReplyAddress.verify(address, configuration: @configuration)
    assert_equal local, local.downcase
    assert_match(/\Areply\+[a-z2-7]+\z/, local)
    assert_operator local.length, :<=, 64
    assert_equal "reply.example.test", address.split("@").last
  end

  def test_verification_accepts_case_folded_addresses
    address = RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    folded = address.upcase

    assert_equal UUID, RecordingStudioNotificationsEmail::ReplyAddress.verify(folded, configuration: @configuration)
  end

  def test_tampered_code_is_rejected
    address = RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    code = address.split("@").first.split("+", 2).last
    code[0] = code[0] == "a" ? "b" : "a"

    assert_nil RecordingStudioNotificationsEmail::ReplyAddress.verify(
      "reply+#{code}@reply.example.test",
      configuration: @configuration
    )
  end

  def test_expired_code_is_rejected_and_a_current_code_still_verifies
    issued_at = Time.utc(2026, 1, 1, 0, 0, 0)
    address = Time.stub(:now, issued_at) do
      RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    end

    assert_equal UUID, Time.stub(:now, issued_at + 30.days) {
      RecordingStudioNotificationsEmail::ReplyAddress.verify(address, configuration: @configuration)
    }
    assert_nil Time.stub(:now, issued_at + 30.days + 1) {
      RecordingStudioNotificationsEmail::ReplyAddress.verify(address, configuration: @configuration)
    }
  end

  def test_non_uuid_delivery_ids_do_not_produce_an_address
    assert_nil RecordingStudioNotificationsEmail::ReplyAddress.address_for("delivery-1", configuration: @configuration)
  end

  def test_blank_reply_domain_does_not_produce_an_address
    @configuration.reply_domain = nil

    assert_nil RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
  end

  def test_invalid_reply_domain_or_expiry_is_rejected
    @configuration.reply_domain = "not a domain"

    assert_raises(RecordingStudioNotificationsEmail::ConfigurationError) do
      RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    end

    @configuration.reply_domain = "reply.example.test"
    @configuration.reply_address_expires_in = 0

    assert_raises(RecordingStudioNotificationsEmail::ConfigurationError) do
      RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: @configuration)
    end
  end

  def test_reply_key_purpose_differs_from_the_delivery_token
    refute_equal RecordingStudioNotificationsEmail::DeliveryToken::PURPOSE,
                 RecordingStudioNotificationsEmail::ReplyAddress::PURPOSE

    token = RecordingStudioNotificationsEmail::DeliveryToken.sign(
      notification: Struct.new(:id).new("notification-1"),
      delivery: Struct.new(:id).new(UUID),
      configuration: @configuration
    )

    assert RecordingStudioNotificationsEmail::DeliveryToken.verify(token, configuration: @configuration)
    assert_nil RecordingStudioNotificationsEmail::ReplyAddress.verify(token, configuration: @configuration)
  end

  def test_a_token_from_another_secret_is_rejected
    other = RecordingStudioNotificationsEmail::Configuration.new
    other.message_verifier = ActiveSupport::MessageVerifier.new("d" * 64, serializer: JSON)
    other.reply_domain = "reply.example.test"
    address = RecordingStudioNotificationsEmail::ReplyAddress.address_for(UUID, configuration: other)

    assert_nil RecordingStudioNotificationsEmail::ReplyAddress.verify(address, configuration: @configuration)
  end

  def test_gem_loads_without_action_mailbox
    script = <<~RUBY
      require "rails"
      require "action_mailer/railtie"
      require "recording_studio_notifications_email"
      abort "action mailbox loaded" if defined?(ActionMailbox)
      abort "reply mailbox loaded" if defined?(RecordingStudioNotificationsEmail::ReplyMailbox)
      puts "ok"
    RUBY
    output, status = Open3.capture2("bundle", "exec", "ruby", "-e", script, chdir: File.expand_path("..", __dir__))

    assert status.success?, output
    assert_equal "ok", output.strip
  end

  def test_load_reply_mailbox_does_nothing_until_action_mailbox_is_loaded
    skip "Action Mailbox is already loaded in this process" if defined?(ActionMailbox)

    assert_nil RecordingStudioNotificationsEmail.load_reply_mailbox!
    refute defined?(RecordingStudioNotificationsEmail::ReplyMailbox)
  end
end
