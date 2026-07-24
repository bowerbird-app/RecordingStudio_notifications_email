# frozen_string_literal: true

register_dummy_notification_types = lambda do
  RecordingStudioNotifications.configure do |config|
    config.rollup_delivery_enabled = true

    # Register notification types used by the dummy app.
    config.notification_types.register(
      :generic,
      label: "Generic notification",
      description: "Default in-app notification",
      icon: :bell,
      default_channels: [:in_app, :email],
      available_channels: [:in_app, :email],
      scope: :optional_root,
      allowed_cadences: %i[individual daily weekly],
      default_cadence: :daily
    )

    config.notification_types.register(
      :page_created,
      label: "Page created",
      description: "A page was created in one of your workspaces",
      icon: :document_text,
      default_channels: [:in_app, :email],
      available_channels: [:in_app, :email],
      scope: :root,
      allowed_cadences: %i[individual daily weekly],
      default_cadence: :daily
    )

    config.notification_types.register(
      :page_comment,
      label: "Page comment",
      description: "A page received a new comment",
      icon: :chat_bubble_left_right,
      default_channels: [:in_app, :email],
      available_channels: [:in_app, :email],
      scope: :root,
      allowed_cadences: %i[individual daily weekly],
      default_cadence: :daily
    )

    config.notification_types.register(
      :system_announcement,
      label: "System announcement",
      description: "Global system notification sent to all users",
      icon: :megaphone,
      default_channels: [:in_app, :email],
      available_channels: [:in_app, :email],
      scope: :global,
      allowed_cadences: %i[individual daily weekly],
      default_cadence: :daily
    )
  end
end

RecordingStudioNotifications.configure do |config|
  # Resolve the current actor for API calls and engine controllers.
  config.actor_resolver = -> { Current.actor }

  # Resolve selected root from RecordingStudio::RootSwitchable helper when available.
  config.current_root_resolver = lambda do |controller:|
    if controller.respond_to?(:current_root_recording, true)
      controller.send(:current_root_recording)
    end
  end

  register_dummy_notification_types.call
end

Rails.application.config.to_prepare do
  register_dummy_notification_types.call

  ActiveSupport::Notifications.unsubscribe("recordings.event_created")

  ActiveSupport::Notifications.subscribe("recordings.event_created") do |_name, _start, _finish, _id, payload|
    Notifications::PageCreatedNotifier.call(payload)
    Notifications::PageCommentNotifier.call(payload)
  end
end
