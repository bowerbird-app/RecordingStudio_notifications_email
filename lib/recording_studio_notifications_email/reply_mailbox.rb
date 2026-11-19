# frozen_string_literal: true

require "action_mailbox/engine"

module RecordingStudioNotificationsEmail
  class ReplyMailbox < ActionMailbox::Base
    def process
      Services::ParseInboundReply.call(mail: mail)
    end
  end
end
