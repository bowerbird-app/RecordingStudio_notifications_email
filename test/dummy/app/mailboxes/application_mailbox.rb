# frozen_string_literal: true

class ApplicationMailbox < ActionMailbox::Base
  routing(/^reply\+/i => "recording_studio_notifications_email/reply")
end
