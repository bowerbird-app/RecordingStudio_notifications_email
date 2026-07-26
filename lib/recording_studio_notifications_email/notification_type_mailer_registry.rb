# frozen_string_literal: true

require_relative "registry"

module RecordingStudioNotificationsEmail
  class NotificationTypeMailerRegistry
    Paths = Data.define(:individual_mailer, :rollup_mailer)

    def initialize
      @paths = Registry.new(label: "notification type mailer")
    end

    def register(notification_type, individual_mailer: nil, rollup_mailer: nil)
      @paths.register(
        notification_type,
        Paths.new(
          individual_mailer: normalize_path(individual_mailer),
          rollup_mailer: normalize_path(rollup_mailer)
        )
      )
    end

    def fetch(notification_type, attribute)
      paths = @paths[notification_type]
      paths&.public_send(attribute)
    end

    def clear!
      @paths.clear!
    end

    private

    def normalize_path(path)
      path.to_s.strip.presence
    end
  end
end