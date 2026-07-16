# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioNotificationsEmail::Configuration.new
  end

  def test_defaults_include_email_channel_and_fallback_templates
    assert_equal :email, @configuration.channel
    assert_equal 30.days, @configuration.signed_reference_expires_in
    assert_equal(
      RecordingStudioNotificationsEmail::Configuration::DEFAULT_TEMPLATE,
      @configuration.template_for(:unknown)
    )
    assert_equal(
      RecordingStudioNotificationsEmail::Configuration::DEFAULT_ROLLUP_TEMPLATE,
      @configuration.rollup_template
    )
  end

  def test_known_values_and_templates_can_be_overridden
    @configuration.merge!("from" => "notifications@example.test", unknown: true)
    @configuration.templates.register(:comment, "mailers/comment")

    assert_equal "notifications@example.test", @configuration.from
    assert_equal "mailers/comment", @configuration.template_for(:comment)
    refute_respond_to @configuration, :unknown
  end

  def test_template_registry_is_safe_during_concurrent_reads_and_writes
    threads = 20.times.map do |index|
      Thread.new do
        @configuration.templates.register(:"type_#{index}", "mailers/#{index}")
        @configuration.templates[:"type_#{index}"]
      end
    end

    assert_equal 20, threads.map(&:value).uniq.size
    assert_equal 22, @configuration.templates.keys.size
  end
end
