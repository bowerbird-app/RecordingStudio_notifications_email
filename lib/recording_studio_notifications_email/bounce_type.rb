# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  # Canonical bounce class for a provider payload.
  #
  # The host maps its provider's field onto +bounce_type+ (top-level or
  # metadata). Only the explicit hard and permanent spellings suppress.
  # A missing, blank, or unrecognised value, including SES Undetermined, is
  # soft: the delivery is updated and no suppression is written.
  module BounceType
    HARD = %w[hard permanent hardbounce hard_bounce].freeze

    module_function

    def normalize(value)
      token = value.to_s.strip.downcase.gsub(/[\s-]+/, "_")
      return :hard if HARD.include?(token)

      :soft
    end

    def permanent?(value)
      normalize(value) == :hard
    end
  end
end
