# frozen_string_literal: true

RecordingStudio.configure do |config|
  # Registered delegated_type recordables (strings or classes)
  config.recordable_types = [ "Workspace", "Folder", "Page", "RecordingStudioCommentable::Comment" ]

  # Require each configured ActiveRecord type to call recording_studio_recordable.
  config.require_recordable_declarations = true

  # Actor resolver for events when no actor is explicitly supplied
  config.actor = -> { Current.actor }

  # Core 6.5 fails closed without a write gate. Delegate to Accessible :edit.
  # Owner grants are seeded with bootstrap_owner_access! / grant_access; those
  # Access writes already run inside Accessible's grant path. Allow the
  # AccessCreationContext only for Access rows, not every write during bootstrap.
  config.authorize_write = lambda { |actor:, root_recording:, recording: nil, parent_recording: nil, recordable: nil, **|
    next false unless defined?(RecordingStudioAccessible)

    target = recording || parent_recording || root_recording
    next false unless target
    next true if defined?(RecordingStudio::Access) &&
                 recordable.is_a?(RecordingStudio::Access) &&
                 RecordingStudioAccessible::AccessCreationContext.allowed?

    RecordingStudioAccessible.authorized?(actor: actor, recording: target, role: :edit)
  }

  # Emit ActiveSupport::Notifications events
  config.event_notifications_enabled = true

  # Idempotency behavior for log_event!
  config.idempotency_mode = :return_existing # or :raise

  # Recordable duplication strategy for revisions
  config.recordable_dup_strategy = :dup

  # Allow RecordingStudioAccessible direct access grants on workspace roots.
  config.enable_capability :accessible, on: "Workspace"
end
