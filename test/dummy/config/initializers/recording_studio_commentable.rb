# frozen_string_literal: true

RecordingStudioCommentable.configure do |config|
  config.layout = "flat_pack_sidebar"
  config.use_recording_studio_trashable_for_destroy = false
  config.rich_text_comments = false
  config.author_display_attributes = {
    "User" => :display_name
  }
end