# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module ThreadMessageId
    def self.for(thread_key, configuration: RecordingStudioNotificationsEmail.configuration)
      key = thread_key.to_s.strip
      return if key.empty?

      domain = configuration.message_id_domain.to_s.strip
      return if domain.empty?
      raise ConfigurationError, "message_id_domain is invalid" unless domain.match?(DeliveryToken::DOMAIN_PATTERN)

      digest = OpenSSL::Digest::SHA256.hexdigest(key)
      "<rsne-thread-#{digest}@#{domain}>"
    end
  end
end
