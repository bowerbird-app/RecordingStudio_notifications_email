# frozen_string_literal: true

class CreateRecordingStudioNotificationsEmailSuppressions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :recording_studio_notifications_email_suppressions,
                 id: :uuid,
                 default: -> { "gen_random_uuid()" } do |t|
      t.string :address, null: false
      t.string :reason, null: false
      t.string :provider, null: false
      t.datetime :lifted_at
      t.timestamps
    end

    add_index :recording_studio_notifications_email_suppressions,
              :address,
              unique: true,
              name: "idx_rsne_suppressions_address"
  end
end
