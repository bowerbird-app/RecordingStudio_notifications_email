require "recording_studio_commentable/comment_routes_helper"

class ApplicationController < ActionController::Base
  include RecordingStudio::ControllerLayout
  include RecordingStudio::RootSwitchable::ControllerSupport
  include RecordingStudioCommentable::CommentRoutesHelper
  helper RecordingStudioNotifications::MenuHelper

  recording_studio_layout { devise_controller? ? "application" : nil }

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  layout :application_layout

  before_action :authenticate_user!
  before_action :set_current_actor

  helper_method :current_recording_studio_actor,
                :workspaces_you_can_change,
                :folders_you_can_use,
                :commentable_recording_comments_path,
                :commentable_all_recording_comments_path,
                :commentable_new_recording_comment_path,
                :commentable_reply_comment_path

  private

  def application_layout
    devise_controller? ? "application" : "flat_pack_sidebar"
  end

  def set_current_actor
    Current.actor = current_user
  end

  def current_recording_studio_actor
    Current.actor || current_user
  end

  def workspaces_you_can_change
    root_recordings_you_can_change.filter_map do |recording|
      recording.recordable if recording.recordable.is_a?(Workspace)
    end
  end

  def folders_you_can_use
    root_ids = root_recordings_you_can_change.map(&:id)
    return Folder.none if root_ids.empty?

    folder_ids = kept_recordings.where(root_recording_id: root_ids, recordable_type: "Folder").pluck(:recordable_id)
    Folder.where(id: folder_ids).order(:name)
  end

  def root_recordings_you_can_change
    @root_recordings_you_can_change ||= RecordingStudioAccessible.root_recordings_for(
      actor: current_user,
      minimum_role: :edit
    )
  end

  def kept_recordings
    RecordingStudio::Recording.where(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
  end
end
