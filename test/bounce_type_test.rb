# frozen_string_literal: true

require "test_helper"

class BounceTypeTest < Minitest::Test
  def test_blank_and_hard_aliases_are_permanent
    [nil, "", "  ", "hard", "Permanent", "HardBounce", "hard-bounce"].each do |value|
      assert RecordingStudioNotificationsEmail::BounceType.permanent?(value), value.inspect
    end
  end

  def test_soft_aliases_are_not_permanent
    ["soft", "Transient", "temporary", "temp", "Soft Bounce"].each do |value|
      assert_equal :soft, RecordingStudioNotificationsEmail::BounceType.normalize(value)
      refute RecordingStudioNotificationsEmail::BounceType.permanent?(value)
    end
  end

  def test_unknown_bounce_type_is_rejected
    error = assert_raises(RecordingStudioNotificationsEmail::InvalidWebhookPayloadError) do
      RecordingStudioNotificationsEmail::BounceType.normalize("undetermined")
    end

    assert_includes error.message, "undetermined"
  end
end
