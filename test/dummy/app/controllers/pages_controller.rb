# frozen_string_literal: true

class PagesController < ApplicationController
  def create
    workspace = Workspace.find(page_params.fetch(:workspace_id))
    root_recording = RecordingStudio.root_recording_for(workspace)

    page = Page.create!(title: page_params.fetch(:title))
    RecordingStudio.record!(
      action: "created",
      recordable: page,
      root_recording: root_recording,
      parent_recording: parent_recording_for(root_recording)
    )

    redirect_to root_path, notice: "Created page '#{page.title}'."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to root_path, alert: "Could not create page: #{e.message}"
  end

  private

  def page_params
    params.require(:page).permit(:title, :workspace_id, :parent_folder_id)
  end

  def parent_recording_for(root_recording)
    folder_id = page_params[:parent_folder_id].to_s
    return root_recording if folder_id.blank?

    folder = Folder.find(folder_id)
    RecordingStudio::Recording.find_by!(
      recordable: folder,
      root_recording: root_recording,
      trashed_at: nil
    )
  end
end
