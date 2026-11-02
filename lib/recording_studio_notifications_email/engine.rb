# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioNotificationsEmail

    initializer "recording_studio_notifications_email.load_config" do |app|
      RecordingStudioNotificationsEmail::Engine.load_configuration(app)
    end

    initializer "recording_studio_notifications_email.register_channel",
                after: "recording_studio_notifications_email.load_config" do
      config.to_prepare { RecordingStudioNotificationsEmail.register! }
    end

    class << self
      def load_configuration(app)
        yaml = yaml_configuration(app)
        RecordingStudioNotificationsEmail.configuration.merge!(yaml) if yaml

        options = app.config.x.recording_studio_notifications_email if app.config.respond_to?(:x)
        RecordingStudioNotificationsEmail.configuration.merge!(options.to_h) if options.respond_to?(:to_h)
      end

      private

      def yaml_configuration(app)
        return unless app.respond_to?(:config_for)

        hash_configuration(app.config_for(:recording_studio_notifications_email))
      rescue Psych::SyntaxError => e
        raise ConfigurationError, "recording_studio_notifications_email.yml is invalid: #{e.message}"
      rescue RuntimeError => e
        missing_configuration(e)
      end

      def hash_configuration(yaml)
        return if yaml.nil?
        return yaml if yaml.respond_to?(:each_pair)

        raise ConfigurationError, "recording_studio_notifications_email.yml must be a hash"
      end

      def missing_configuration(error)
        raise error unless error.message.include?("No such file")

        nil
      end
    end
  end
end
