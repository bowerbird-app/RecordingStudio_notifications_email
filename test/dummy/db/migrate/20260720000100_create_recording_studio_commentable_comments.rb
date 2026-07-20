# frozen_string_literal: true

class CreateRecordingStudioCommentableComments < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_comments, id: :uuid do |t|
      t.text :body, null: false
      t.string :author_type
      t.uuid :author_id

      t.timestamps
    end

    add_index :recording_studio_comments, %i[author_type author_id]
  end
end
