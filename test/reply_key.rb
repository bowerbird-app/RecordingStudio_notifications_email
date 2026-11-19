# frozen_string_literal: true

module ReplyKey
  def with_reply_key(secret, &)
    @reply_key_box = { key: ActiveSupport::KeyGenerator.new(secret, iterations: 1) }
    box = @reply_key_box
    application = Object.new
    application.define_singleton_method(:key_generator) { box[:key] }
    Rails.stub(:application, application, &)
  end

  def use_reply_key(secret)
    @reply_key_box[:key] = ActiveSupport::KeyGenerator.new(secret, iterations: 1)
  end
end
