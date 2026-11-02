# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class DummyScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "signed-in screens use the sidebar layout and devise keeps application" do
    get new_user_session_path

    assert_response :success
    refute_includes response.body, "This workspace"
    assert_includes response.body, "Login"

    sign_in_user("layout-reader@example.com")
    get root_path

    assert_response :success
    assert_includes response.body, "Page mail"
    assert_includes response.body, "This workspace"
    assert_includes response.body, 'name="page[workspace_id]"'
  end

  test "the workspace outline lists only the current workspace" do
    owner = sign_in_user("outline-owner@example.com")
    hidden = Workspace.create!(name: "Hidden Outline Workspace")
    grant_workspace(owner, hidden)
    hidden_root = RecordingStudio.root_recording_for(hidden)
    secret = Page.create!(title: "Secret outline")
    RecordingStudio.record!(
      action: "created",
      recordable: secret,
      root_recording: hidden_root,
      parent_recording: hidden_root
    )

    sign_out owner
    visitor = sign_in_user("outline-visitor@example.com")
    visible = Workspace.create!(name: "Visible Outline Workspace")
    grant_workspace(visitor, visible)
    visible_root = RecordingStudio.root_recording_for(visible)
    page = Page.create!(title: "Visible outline")
    RecordingStudio.record!(
      action: "created",
      recordable: page,
      root_recording: visible_root,
      parent_recording: visible_root
    )

    get docs_recordings_tree_path

    assert_response :success
    assert_includes response.body, "Page: Visible outline"
    refute_includes response.body, "Workspace: Visible Outline Workspace"
    refute_includes response.body, "Hidden Outline Workspace"
    refute_includes response.body, "Secret outline"
    refute_includes response.body, "Access:"
    refute_includes response.body, "Unknown actor"

    get docs_gem_views_path
    assert_includes response.body, "app/views/recording_studio_notifications_email/"
    assert_includes response.body, "notification_mailer/notification.html.erb"
    refute_includes response.body, "app/views/recording_studio_notifications_email/notification_mailer/notification.html.erb"

    get docs_methods_path
    assert_includes response.body, "mark_delivered!"

    get new_system_notifications_path
    assert_includes response.body, "people who can open this workspace"
    refute_includes response.body, "every user"
    refute_includes response.body, "Send to all users"
  end

  private

  def sign_in_user(email)
    user = User.create!(email: email, password: "Password123!", password_confirmation: "Password123!")
    sign_in user
    user
  end

  def grant_workspace(actor, workspace)
    recording = RecordingStudio.root_recording_for(workspace)
    RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor).value!
    recording
  end
end
