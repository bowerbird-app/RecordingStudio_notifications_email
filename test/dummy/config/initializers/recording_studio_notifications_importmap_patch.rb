# frozen_string_literal: true

# Monkey patch for RecordingStudioNotifications importmap path registration.
# Keeps host apps working on boot orders where the engine initializer guard
# skips adding its config/importmap.rb path.
Rails.application.config.after_initialize do
  next unless defined?(RecordingStudioNotifications::Engine)
  next unless Rails.application.config.respond_to?(:importmap)

  importmap_paths = Rails.application.config.importmap.paths
  engine_importmap_path = RecordingStudioNotifications::Engine.root.join("config/importmap.rb")

  unless importmap_paths.map(&:to_s).include?(engine_importmap_path.to_s)
    importmap_paths << engine_importmap_path
  end
end
