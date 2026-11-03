# frozen_string_literal: true

require "test_helper"

class EngineConfigurationTest < Minitest::Test
  def setup
    @roots = []
  end

  def teardown
    RecordingStudioNotificationsEmail.reset_configuration!
    @roots.each { |root| FileUtils.remove_entry(root) if File.directory?(root) }
  end

  def test_load_configuration_is_private
    refute_respond_to RecordingStudioNotificationsEmail::Engine, :load_configuration

    assert_raises(NoMethodError) do
      RecordingStudioNotificationsEmail::Engine.load_configuration(Object.new)
    end
  end

  def test_engine_merges_yaml_and_application_configuration
    RecordingStudioNotificationsEmail.reset_configuration!
    application_options = Object.new
    application_options.define_singleton_method(:recording_studio_notifications_email) do
      { reply_to: "reply@example.test" }
    end
    config = Object.new
    config.define_singleton_method(:x) { application_options }
    app = app_with_config_for(->(_name) { { "from" => "from@example.test" } })
    app.define_singleton_method(:config) { config }

    load_config_initializer.block.call(app)

    assert_equal "from@example.test", RecordingStudioNotificationsEmail.configuration.from
    assert_equal "reply@example.test", RecordingStudioNotificationsEmail.configuration.reply_to
  end

  def test_missing_yaml_leaves_configuration_in_place
    RecordingStudioNotificationsEmail.reset_configuration!
    RecordingStudioNotificationsEmail.configuration.from = "already@example.test"
    called = false
    app = app_with_config_for(lambda { |_name|
      called = true
      flunk "config_for should not run when the yaml file is absent"
    }, file: false)

    load_config_initializer.block.call(app)

    refute called
    assert_equal "already@example.test", RecordingStudioNotificationsEmail.configuration.from
  end

  def test_invalid_yaml_raises_configuration_error
    syntax_error = Psych::SyntaxError.new("recording_studio_notifications_email.yml", 1, 1, 0, "bad indent", "context")
    app = app_with_config_for(->(_name) { raise syntax_error })

    error = assert_raises(RecordingStudioNotificationsEmail::ConfigurationError) do
      load_config_initializer.block.call(app)
    end

    assert_includes error.message, "invalid"
  end

  def test_non_hash_yaml_raises_configuration_error
    app = app_with_config_for(->(_name) { "from@example.test" })

    error = assert_raises(RecordingStudioNotificationsEmail::ConfigurationError) do
      load_config_initializer.block.call(app)
    end

    assert_includes error.message, "must be a hash"
  end

  def test_unexpected_config_load_errors_propagate
    app = app_with_config_for(->(_name) { raise "disk failed" })

    assert_raises(RuntimeError) { load_config_initializer.block.call(app) }
  end

  private

  def app_with_config_for(reader, file: true)
    root = Dir.mktmpdir
    @roots << root
    if file
      FileUtils.mkdir_p(File.join(root, "config"))
      File.write(File.join(root, "config/recording_studio_notifications_email.yml"), "{}\n")
    end

    config = Object.new
    app = Object.new
    app.define_singleton_method(:root) { Pathname(root) }
    app.define_singleton_method(:config_for, reader)
    app.define_singleton_method(:config) { config }
    app
  end

  def load_config_initializer
    RecordingStudioNotificationsEmail::Engine.initializers.find do |candidate|
      candidate.name == "recording_studio_notifications_email.load_config"
    end
  end
end
