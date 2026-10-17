# frozen_string_literal: true

require "test_helper"

class SuppressionTest < Minitest::Test
  def test_normalizes_mailbox_case_and_display_name
    assert_equal "person@example.test",
                 RecordingStudioNotificationsEmail::Suppression.normalize_address(" Person <Person@Example.Test> ")
  end

  def test_rejects_blank_and_invalid_addresses
    assert_raises(ArgumentError) do
      RecordingStudioNotificationsEmail::Suppression.normalize_address("   ")
    end

    assert_raises(ArgumentError) do
      RecordingStudioNotificationsEmail::Suppression.normalize_address("not-an-address")
    end

    assert_raises(ArgumentError) do
      RecordingStudioNotificationsEmail::Suppression.normalize_address("person@example.test\n")
    end
  end

  def test_suppress_requires_a_provider
    assert_raises(ArgumentError) do
      RecordingStudioNotificationsEmail::Suppression.suppress!(
        address: "person@example.test",
        reason: "bounce",
        provider: "  "
      )
    end
  end
end
