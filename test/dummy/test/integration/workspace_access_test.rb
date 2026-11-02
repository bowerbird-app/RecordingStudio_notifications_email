# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class WorkspaceAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "a person can create a page in a workspace they can change" do
    editor = sign_in_user("page-editor@example.com")
    workspace = Workspace.create!(name: "Editable Workspace")
    grant_workspace(editor, workspace)

    assert_difference -> { Page.where(title: "Launch plan").count }, 1 do
      post pages_path, params: { page: { title: "Launch plan", workspace_id: workspace.id } }
    end

    assert_redirected_to pages_path
    follow_redirect!
    assert_includes response.body, "Launch plan"
  end

  test "an ungranted person cannot create a page or see that workspace" do
    owner = sign_in_user("page-owner@example.com")
    workspace = Workspace.create!(name: "Private Pages Workspace")
    grant_workspace(owner, workspace)
    sign_out owner
    sign_in_user("page-stranger@example.com")

    assert_no_difference -> { Page.count } do
      post pages_path, params: { page: { title: "Sneaky page", workspace_id: workspace.id } }
    end

    assert_redirected_to pages_path
    assert_equal "You don't have access to this workspace. Ask someone to invite you.", flash[:alert]

    get pages_path
    refute_includes response.body, "Private Pages Workspace"
    refute_includes response.body, "Sneaky page"

    get root_path
    refute_includes response.body, "Private Pages Workspace"
  end

  test "only a workspace admin can send a notice" do
    admin = sign_in_user("notice-admin@example.com")
    workspace = Workspace.create!(name: "Notice Workspace")
    grant_workspace(admin, workspace)
    outsider = User.create!(
      email: "notice-outsider@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    other_workspace = Workspace.create!(name: "Elsewhere Workspace")
    grant_workspace(outsider, other_workspace)

    assert_difference -> { RecordingStudioNotifications::Notification.where(recipient: admin).count }, 1 do
      assert_no_difference -> { RecordingStudioNotifications::Notification.where(recipient: outsider).count } do
        post system_notifications_path, params: {
          system_notification: { title: "Tonight", body: "We will be back at 10." }
        }
      end
    end
    assert_redirected_to new_system_notifications_path
    assert_equal "Notice sent to 1 person in this workspace.", flash[:notice]

    sign_out admin
    editor = sign_in_user("notice-editor@example.com")
    RecordingStudioAccessible.grant_access(
      recording: RecordingStudio.root_recording_for(workspace),
      actor: editor,
      role: :edit,
      manager_actor: admin
    ).value!

    assert_no_difference -> { RecordingStudioNotifications::Notification.count } do
      post system_notifications_path, params: {
        system_notification: { title: "Nope", body: "Should not send." }
      }
    end

    assert_redirected_to root_path
    assert_equal "You don't have access to send a notice from this workspace.", flash[:alert]
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