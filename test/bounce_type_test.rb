# frozen_string_literal: true

require "test_helper"

class BounceTypeTest < Minitest::Test
  def test_explicit_hard_aliases_are_permanent
    ["hard", "Permanent", "HardBounce", "hard-bounce", "HARD BOUNCE"].each do |value|
      assert_equal :hard, RecordingStudioNotificationsEmail::BounceType.normalize(value)
      assert RecordingStudioNotificationsEmail::BounceType.permanent?(value), value.inspect
    end
  end

  def test_soft_aliases_are_not_permanent
    ["soft", "Transient", "temporary", "temp", "Soft Bounce", "SoftBounce"].each do |value|
      assert_equal :soft, RecordingStudioNotificationsEmail::BounceType.normalize(value)
      refute RecordingStudioNotificationsEmail::BounceType.permanent?(value)
    end
  end

  def test_missing_blank_and_unknown_values_are_soft
    [nil, "", "  ", "undetermined", "Undetermined", "PermanentFailure"].each do |value|
      assert_equal :soft, RecordingStudioNotificationsEmail::BounceType.normalize(value)
      refute RecordingStudioNotificationsEmail::BounceType.permanent?(value), value.inspect
    end
  end
end
