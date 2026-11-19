# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module ReplyAddress
    PURPOSE = "recording_studio_notifications_email.reply_address"
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    ALPHABET = "abcdefghijklmnopqrstuvwxyz234567"
    MAC_BYTES = 10
    TOKEN_BYTES = 30
    LOCAL_LIMIT = 64

    class << self
      def address_for(delivery, configuration: RecordingStudioNotificationsEmail.configuration)
        code = code_for(delivery, configuration: configuration)
        return unless code

        domain = normalized_domain(configuration.reply_domain)
        return unless domain

        local = "reply+#{code}"
        return if local.length > LOCAL_LIMIT

        "#{local}@#{domain}"
      end

      def code_for(delivery, configuration: RecordingStudioNotificationsEmail.configuration)
        uuid = normalize_uuid(delivery)
        return unless uuid

        payload = uuid_bytes(uuid) + [expiry_at(configuration)].pack("N")
        mac = OpenSSL::HMAC.digest("SHA256", signing_key(configuration), payload).byteslice(0, MAC_BYTES)
        encode_base32(payload + mac)
      end

      def verify(token, configuration: RecordingStudioNotificationsEmail.configuration)
        raw = decode_base32(extract_code(token))
        return unless raw&.bytesize == TOKEN_BYTES

        payload = raw.byteslice(0, TOKEN_BYTES - MAC_BYTES)
        mac = raw.byteslice(TOKEN_BYTES - MAC_BYTES, MAC_BYTES)
        expected = OpenSSL::HMAC.digest("SHA256", signing_key(configuration), payload).byteslice(0, MAC_BYTES)
        return unless same_mac?(mac, expected)
        return if Time.now.to_i > payload.byteslice(16, 4).unpack1("N")

        uuid_from_bytes(payload.byteslice(0, 16))
      end

      def normalized_domain(value)
        domain = value.to_s.strip.downcase
        return if domain.empty?
        return domain if domain.match?(DeliveryToken::DOMAIN_PATTERN)

        raise ConfigurationError, "reply_domain is invalid"
      end

      private

      def normalize_uuid(delivery)
        value = delivery.respond_to?(:id) ? delivery.id : delivery
        text = value.to_s.strip.downcase
        text if text.match?(UUID)
      end

      def expiry_at(configuration)
        Time.now.to_i + expiry_seconds(configuration)
      end

      def expiry_seconds(configuration)
        value = configuration.reply_address_expires_in
        duration = value.is_a?(Numeric) || value.is_a?(ActiveSupport::Duration)
        return value.to_i if duration && value.to_f.positive?

        raise ConfigurationError, "reply_address_expires_in must be a positive duration"
      end

      def signing_key(configuration)
        secret = verifier_secret(configuration)
        digest = OpenSSL::Digest::SHA256.hexdigest("#{PURPOSE}\0#{secret}")
        key_cache.synchronize do
          key_cache.store[digest] ||= ActiveSupport::KeyGenerator.new(secret).generate_key(PURPOSE, 32)
        end
      end

      def verifier_secret(configuration)
        secret = configuration.message_verifier ? secret_from(configuration.message_verifier) : rails_secret
        return secret if secret.present?

        raise ConfigurationError, "configure message_verifier before signing a reply address"
      end

      def secret_from(verifier)
        verifier.instance_variable_get(:@secret)
      end

      def rails_secret
        return unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application

        Rails.application.secret_key_base
      end

      def key_cache
        @key_cache ||= KeyCache.new
      end

      def extract_code(token)
        text = token.to_s.strip
        text = text[/<([^>]+)>/, 1] || text
        local = text.split("@", 2).first.to_s
        code = local.downcase.start_with?("reply+") ? local.split("+", 2).last.to_s : local
        code.downcase.delete_suffix(">")
      end

      def same_mac?(mac, expected)
        return false unless mac.bytesize == expected.bytesize

        ActiveSupport::SecurityUtils.secure_compare(mac, expected)
      end

      def uuid_bytes(uuid)
        [uuid.delete("-")].pack("H*")
      end

      def uuid_from_bytes(bytes)
        hex = bytes.unpack1("H*")
        "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
      end

      def encode_base32(bytes)
        buffer = 0
        bits = 0
        encoded = +""
        bytes.each_byte do |byte|
          buffer = (buffer << 8) | byte
          bits += 8
          while bits >= 5
            bits -= 5
            encoded << ALPHABET[(buffer >> bits) & 31]
          end
        end
        encoded
      end

      def decode_base32(text)
        return unless text.match?(/\A[a-z2-7]+\z/)

        buffer = 0
        bits = 0
        decoded = +"".b
        text.each_char do |char|
          buffer = (buffer << 5) | ALPHABET.index(char)
          bits += 5
          next unless bits >= 8

          bits -= 8
          decoded << ((buffer >> bits) & 0xFF)
        end
        decoded
      end
    end

    class KeyCache
      attr_reader :store

      def initialize
        @store = {}
        @mutex = Mutex.new
      end

      def synchronize(&)
        @mutex.synchronize(&)
      end
    end
    private_constant :KeyCache
  end
end
