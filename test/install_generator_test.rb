# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_notifications_email/install/install_generator"

class InstallGeneratorTest < Minitest::Test
  def test_generator_is_a_rails_generator
    assert_operator RecordingStudioNotificationsEmail::Generators::InstallGenerator, :<, Rails::Generators::Base
  end

  def test_generator_copies_the_initializer
    Dir.mktmpdir do |destination|
      RecordingStudioNotificationsEmail::Generators::InstallGenerator.start([], destination_root: destination)
      path = File.join(destination, "config/initializers/recording_studio_notifications_email.rb")

      assert File.file?(path)
      source = File.read(path)
      assert_includes source, "RecordingStudioNotificationsEmail.configure"
      assert_includes source, "config.from"
    end
  end
end
