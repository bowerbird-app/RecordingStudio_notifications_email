# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_notifications_email/migrations/migrations_generator"

class MigrationsGeneratorTest < Minitest::Test
  def test_migration_creates_a_unique_normalised_address_table
    path = File.expand_path(
      "../db/migrate/20261017000000_create_recording_studio_notifications_email_suppressions.rb",
      __dir__
    )
    source = File.read(path)

    assert_includes source, "recording_studio_notifications_email_suppressions"
    assert_includes source, "t.string :address, null: false"
    assert_includes source, "t.string :reason, null: false"
    assert_includes source, "t.string :provider, null: false"
    assert_includes source, "t.datetime :lifted_at"
    assert_includes source, "t.timestamps"
    assert_includes source, "unique: true"
  end

  def test_generator_is_a_rails_generator
    assert_operator RecordingStudioNotificationsEmail::Generators::MigrationsGenerator, :<, Rails::Generators::Base
  end

  def test_generator_reports_when_the_gem_has_no_migrations
    Dir.mktmpdir do |destination|
      generator = RecordingStudioNotificationsEmail::Generators::MigrationsGenerator.new(
        [],
        {},
        destination_root: destination
      )

      Dir.stub(:glob, []) do
        assert_nil generator.copy_migrations
      end
    end
  end

  def test_generator_copies_the_migration_and_skips_an_existing_copy
    Dir.mktmpdir do |destination|
      FileUtils.mkdir_p(File.join(destination, "db/migrate"))
      generator_class = RecordingStudioNotificationsEmail::Generators::MigrationsGenerator

      generator_class.start([], destination_root: destination)
      pattern = "*_create_recording_studio_notifications_email_suppressions.rb"
      copied = Dir.glob(File.join(destination, "db/migrate", pattern))
      assert_equal 1, copied.size
      assert_includes File.read(copied.first), "idx_rsne_suppressions_address"

      generator_class.start([], destination_root: destination)
      assert_equal 1, Dir.glob(File.join(destination, "db/migrate/*suppressions.rb")).size
    end
  end
end
