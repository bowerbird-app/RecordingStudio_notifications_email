# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioNotificationsEmail

    initializer "recording_studio_notifications_email.load_config" do |app|
      RecordingStudioNotificationsEmail::Engine.send(:load_configuration, app)
    end

    initializer "recording_studio_notifications_email.register_channel",
                after: "recording_studio_notifications_email.load_config" do
      config.to_prepare { RecordingStudioNotificationsEmail.register! }
    end

    class << self
      private

      def load_configuration(app)
        yaml = yaml_configuration(app)
        RecordingStudioNotificationsEmail.configuration.merge!(yaml) if yaml

        options = app.config.x.recording_studio_notifications_email if app.config.respond_to?(:x)
        RecordingStudioNotificationsEmail.configuration.merge!(options.to_h) if options.respond_to?(:to_h)
      end

      def yaml_configuration(app)
        return unless app.respond_to?(:config_for)
        return unless yaml_file(app)&.exist?

        hash_configuration(app.config_for(:recording_studio_notifications_email))
      rescue Psych::SyntaxError => e
        raise ConfigurationError, "recording_studio_notifications_email.yml is invalid: #{e.message}"
      end

      def yaml_file(app)
        return unless app.respond_to?(:root) && app.root

        Pathname(app.root).join("config/recording_studio_notifications_email.yml")
      end

      def hash_configuration(yaml)
        return if yaml.nil?
        return yaml if yaml.respond_to?(:each_pair)

        raise ConfigurationError, "recording_studio_notifications_email.yml must be a hash"
      end
    end
  end
end
