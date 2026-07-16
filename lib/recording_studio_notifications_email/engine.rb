# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioNotificationsEmail

    initializer "recording_studio_notifications_email.load_config" do |app|
      yaml = app.config_for(:recording_studio_notifications_email) if app.respond_to?(:config_for)
      RecordingStudioNotificationsEmail.configuration.merge!(yaml) if yaml.respond_to?(:each)

      options = app.config.x.recording_studio_notifications_email if app.config.respond_to?(:x)
      RecordingStudioNotificationsEmail.configuration.merge!(options.to_h) if options.respond_to?(:to_h)
    rescue StandardError => error
      Rails.logger&.warn("[RecordingStudioNotificationsEmail] configuration was not loaded: #{error.message}")
    end

    initializer "recording_studio_notifications_email.register_channel",
                after: "recording_studio_notifications_email.load_config" do
      config.to_prepare { RecordingStudioNotificationsEmail.register! }
    end
  end
end
