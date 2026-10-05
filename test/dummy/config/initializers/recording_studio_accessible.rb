# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  # Accessible 0.11 only grants to allowlisted actor types.
  config.access_actor_types = ["User"]

  # Dummy bootstrap rule: allow first grant on a recording when no direct access
  # grants exist yet, otherwise require admin permission.
  config.access_management_authorizer = lambda do |recording:, actor:, **|
    next false unless actor.present? && recording.present?

    has_grants = RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(recording).exists?
    next true unless has_grants

    RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: "admin")
  end
end
