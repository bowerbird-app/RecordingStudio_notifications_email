require "recording_studio_commentable/comment_routes_helper"

class ApplicationController < ActionController::Base
  include RecordingStudio::RootSwitchable::ControllerSupport
  include RecordingStudioCommentable::CommentRoutesHelper
  helper RecordingStudioNotifications::MenuHelper

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  layout :application_layout

  before_action :authenticate_user!
  before_action :set_current_actor

  helper_method :current_recording_studio_actor,
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
end
