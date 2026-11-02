# frozen_string_literal: true

require "test_helper"

class InboxScopeTest < ActiveSupport::TestCase
  test "the inbox scope comes from notifications config and not a local patch" do
    configuration = RecordingStudioNotifications.configuration

    assert_equal "current_root", configuration.default_inbox_scope
    assert_equal "current_root", configuration.inbox_scope_for(nil)
    assert_equal "current_root", configuration.inbox_scope_for("somewhere")
    assert_equal "all", configuration.inbox_scope_for("all")
    refute File.exist?(Rails.root.join("config/initializers/recording_studio_notifications_scope_patch.rb"))
  end
end
