# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  # Canonical bounce class for a provider payload.
  #
  # The host maps its provider's field onto +bounce_type+ (top-level or
  # metadata). This normalises the common spellings. A blank value is a hard
  # bounce, matching +mark_bounced!+ with no type. Anything else raises so a
  # host mapping typo does not silently drop or keep a suppression.
  module BounceType
    HARD = %w[hard permanent hardbounce hard_bounce].freeze
    SOFT = %w[soft transient temporary temp softbounce soft_bounce].freeze

    module_function

    def normalize(value)
      token = value.to_s.strip.downcase.gsub(/[\s-]+/, "_")
      return :hard if token.empty?
      return :hard if HARD.include?(token)
      return :soft if SOFT.include?(token)

      raise InvalidWebhookPayloadError, "unsupported bounce_type: #{value}"
    end

    def permanent?(value)
      normalize(value) == :hard
    end
  end
end
