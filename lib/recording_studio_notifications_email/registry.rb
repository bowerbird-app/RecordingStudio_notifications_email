# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  # Small copy-on-read registry used by runtime extension points.
  class Registry
    def initialize(label:)
      @label = label
      @entries = {}
      @mutex = Mutex.new
    end

    def register(key, value = nil, &block)
      normalized_key = normalize_key!(key)
      entry = value || block
      raise ArgumentError, "#{@label} is required" if entry.nil?

      @mutex.synchronize { @entries[normalized_key] = entry }
      entry
    end

    def fetch(key, fallback = nil)
      normalized_key = normalize_key!(key)

      @mutex.synchronize do
        return @entries.fetch(normalized_key) if @entries.key?(normalized_key)
        return @entries.fetch(normalize_key!(fallback)) unless fallback.nil?

        @entries.fetch(normalized_key)
      end
    end

    def [](key)
      normalized_key = normalize_key!(key)
      @mutex.synchronize { @entries[normalized_key] }
    rescue ArgumentError
      nil
    end

    def registered?(key)
      normalized_key = normalize_key!(key)
      @mutex.synchronize { @entries.key?(normalized_key) }
    rescue ArgumentError
      false
    end

    def keys
      @mutex.synchronize { @entries.keys.sort_by(&:to_s).freeze }
    end

    def clear!
      @mutex.synchronize { @entries.clear }
      self
    end

    private

    def normalize_key!(key)
      normalized = key.to_s.strip
      raise ArgumentError, "#{@label} key is required" if normalized.empty?

      normalized.to_sym
    end
  end
end
