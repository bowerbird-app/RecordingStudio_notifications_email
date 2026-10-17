# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module NotificationTypeMailerRegistration
    def register(key, individual_mailer: nil, rollup_mailer: nil, **attributes)
      definition = super(key, **attributes)
      RecordingStudioNotificationsEmail.notification_type_mailers.register(
        key,
        individual_mailer: individual_mailer,
        rollup_mailer: rollup_mailer
      )
      definition
    end
  end
end

registry = RecordingStudioNotifications::NotificationTypeRegistry
parameters = registry.instance_method(:register).parameters
# Named keywords only. Notifications 0.9's **options rejects unknown keys,
# so a catch-all is not support for these template paths.
supports_mailer_paths = %i[individual_mailer rollup_mailer].all? do |attribute|
  parameters.any? { |_kind, name| name == attribute }
end
registry.prepend(RecordingStudioNotificationsEmail::NotificationTypeMailerRegistration) unless supports_mailer_paths
