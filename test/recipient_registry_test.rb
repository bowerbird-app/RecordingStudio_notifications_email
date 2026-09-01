# frozen_string_literal: true

require "test_helper"

class RecipientRegistryTest < Minitest::Test
  Recipient = Struct.new(:email)
  class SpecialRecipient < Recipient
  end

  def setup
    @registry = RecordingStudioNotificationsEmail::RecipientRegistry.new
  end

  def test_defaults_to_recipient_email
    assert_equal "person@example.test", @registry.resolve(Recipient.new(" person@example.test "))
  end

  def test_registered_ancestor_resolver_overrides_default
    @registry.register(Recipient) { |_recipient| ["one@example.test", "two@example.test"] }

    assert_equal %w[one@example.test two@example.test], @registry.resolve(SpecialRecipient.new("ignored@example.test"))
  end

  def test_blank_resolution_fails_explicitly
    error = assert_raises(ArgumentError) { @registry.resolve(Recipient.new(nil)) }

    assert_equal "recipient did not resolve to an email address", error.message
  end

  def test_invalid_resolver_is_rejected
    assert_raises(ArgumentError) { @registry.register(Recipient, Object.new) }
  end

  def test_header_injection_and_malformed_addresses_are_rejected
    assert_raises(ArgumentError) { @registry.resolve(Recipient.new("person@example.test\nBcc: victim@example.test")) }
    assert_raises(ArgumentError) { @registry.resolve(Recipient.new("not-an-address")) }
  end
end
