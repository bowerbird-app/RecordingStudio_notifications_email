# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  # Resolves an email destination without coupling the adapter to a User model.
  class RecipientRegistry
    def initialize
      @resolvers = {}
      @mutex = Mutex.new
    end

    def register(type, resolver = nil, &block)
      callable = resolver || block
      raise ArgumentError, "recipient resolver must respond to call" unless callable.respond_to?(:call)

      key = normalize_type!(type)
      @mutex.synchronize { @resolvers[key] = callable }
      callable
    end

    def resolve(recipient)
      raise ArgumentError, "recipient is required" if recipient.nil?

      resolver = resolver_for(recipient)
      value = resolver ? resolver.call(recipient) : default_address(recipient)
      normalize_address(value)
    end

    def registered?(type)
      key = normalize_type!(type)
      @mutex.synchronize { @resolvers.key?(key) }
    rescue ArgumentError
      false
    end

    def keys
      @mutex.synchronize { @resolvers.keys.sort.freeze }
    end

    def clear!
      @mutex.synchronize { @resolvers.clear }
      self
    end

    private

    def resolver_for(recipient)
      keys = recipient.class.ancestors.filter_map { |ancestor| ancestor.name.to_s.presence }
      @mutex.synchronize do
        keys.each do |key|
          resolver = @resolvers[key]
          return resolver if resolver
        end
        @resolvers["default"]
      end
    end

    def default_address(recipient)
      recipient.email if recipient.respond_to?(:email)
    end

    def normalize_address(value)
      addresses = Array(value).flatten.compact.filter_map { |address| normalize_one_address(address) }.uniq
      raise ArgumentError, "recipient did not resolve to an email address" if addresses.empty?

      addresses.one? ? addresses.first : addresses.freeze
    end

    def normalize_one_address(value)
      address = value.to_s.strip
      return if address.empty?
      raise ArgumentError, "recipient resolved to an invalid email address" if address.match?(/[\r\n]/)

      parsed = Mail::Address.new(address)
      unless parsed.address.present? && parsed.domain.present?
        raise ArgumentError, "recipient resolved to an invalid email address"
      end

      address
    rescue Mail::Field::ParseError
      raise ArgumentError, "recipient resolved to an invalid email address"
    end

    def normalize_type!(type)
      value = type.is_a?(Module) ? type.name : type.to_s
      value = value.strip
      raise ArgumentError, "recipient type is required" if value.empty?

      value
    end
  end
end
