# frozen_string_literal: true

class PagesController < ApplicationController
  def index
    @workspaces = workspaces_you_can_change
    @folders = folders_you_can_use
    page_recordings = kept_recordings.where(
      root_recording_id: root_recordings_you_can_change.map(&:id),
      recordable_type: "Page"
    )
    @recordings_by_page_id = page_recordings.index_by(&:recordable_id)
    @pages = Page.where(id: page_recordings.map(&:recordable_id)).order(created_at: :desc)
  end

  def create
    workspace = Workspace.find(page_params.fetch(:workspace_id))
    root_recording = RecordingStudio.root_recording_for(workspace)
    unless RecordingStudioAccessible.authorized?(actor: current_user, recording: root_recording, role: :edit)
      redirect_to pages_path, alert: "You don't have access to this workspace. Ask someone to invite you."
      return
    end

    page = Page.create!(title: page_params.fetch(:title))
    RecordingStudio.record!(
      action: "created",
      recordable: page,
      root_recording: root_recording,
      parent_recording: parent_recording_for(root_recording)
    )

    redirect_to pages_path, notice: "Created page '#{page.title}'."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to pages_path, alert: "Could not create page: #{e.message}"
  end

  private

  def page_params
    params.require(:page).permit(:title, :workspace_id, :parent_folder_id)
  end

  def parent_recording_for(root_recording)
    folder_id = page_params[:parent_folder_id].to_s
    return root_recording if folder_id.blank?

    folder = Folder.find(folder_id)
    kept_recordings.find_by!(
      recordable: folder,
      root_recording: root_recording
    )
  end
end
