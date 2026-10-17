# frozen_string_literal: true

require "active_record"
require "mail"

module RecordingStudioNotificationsEmail
  class SuppressedRecipientError < StandardError; end

  # One row per normalised mailbox. A lifted row stays so a later suppress!
  # can clear lifted_at instead of inserting a second address.
  class Suppression < ActiveRecord::Base
    self.table_name = "recording_studio_notifications_email_suppressions"

    REASONS = %w[bounce complaint unsubscribed].freeze

    validates :address, :reason, :provider, presence: true
    validates :address, uniqueness: true
    validates :reason, inclusion: { in: REASONS }

    class << self
      def normalize_address(value)
        raw = value.to_s
        raise ArgumentError, "email address is invalid" if raw.match?(/[\r\n]/)

        stripped = raw.strip
        raise ArgumentError, "email address is required" if stripped.empty?

        mailbox_address(stripped)
      end

      def mailbox_address(raw)
        parsed = Mail::Address.new(raw)
        mailbox = parsed.address.to_s.strip.downcase
        raise ArgumentError, "email address is invalid" if mailbox.empty? || parsed.domain.blank?

        mailbox
      rescue Mail::Field::ParseError
        raise ArgumentError, "email address is invalid"
      end
      private :mailbox_address

      def suppressed?(address)
        normalized = normalize_address(address)
        where(address: normalized, lifted_at: nil).exists?
      end

      def suppress!(address:, reason:, provider:)
        normalized = normalize_address(address)
        normalized_provider = provider.to_s.strip.downcase
        raise ArgumentError, "provider is required" if normalized_provider.empty?

        record = find_or_initialize_by(address: normalized)
        record.reason = reason.to_s
        record.provider = normalized_provider
        record.lifted_at = nil
        record.save!
        record
      end

      def lift!(address, at: Time.current)
        record = find_by!(address: normalize_address(address))
        record.update!(lifted_at: record.lifted_at || at)
        record
      end
    end
  end
end
