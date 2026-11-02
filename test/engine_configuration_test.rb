# frozen_string_literal: true

require "test_helper"

class EngineConfigurationTest < Minitest::Test
  def teardown
    RecordingStudioNotificationsEmail.reset_configuration!
  end

  def test_engine_merges_yaml_and_application_configuration
    RecordingStudioNotificationsEmail.reset_configuration!
    application_options = Object.new
    application_options.define_singleton_method(:recording_studio_notifications_email) do
      { reply_to: "reply@example.test" }
    end
    config = Object.new
    config.define_singleton_method(:x) { application_options }
    app = Object.new
    app.define_singleton_method(:config_for) { |_name| { "from" => "from@example.test" } }
    app.define_singleton_method(:config) { config }

    load_config_initializer.block.call(app)

    assert_equal "from@example.test", RecordingStudioNotificationsEmail.configuration.from
    assert_equal "reply@example.test", RecordingStudioNotificationsEmail.configuration.reply_to
  end

  private

  def load_config_initializer
    RecordingStudioNotificationsEmail::Engine.initializers.find do |candidate|
      candidate.name == "recording_studio_notifications_email.load_config"
    end
  end
end
