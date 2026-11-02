# frozen_string_literal: true

require "test_helper"

class DummySurfaceTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_template_leftovers_are_gone
    [
      "test/dummy/install_page.html",
      "test/dummy/app/javascript/controllers/hello_controller.js",
      "test/dummy/app/views/makeup_artist/custom_examples/.keep",
      "test/dummy/.github/workflows/ci.yml",
      "test/dummy/.github/dependabot.yml"
    ].each do |relative|
      refute File.exist?(File.join(ROOT, relative)), relative
    end
  end

  def test_dummy_test_database_comes_from_the_loaded_configuration
    require "active_record"
    require "erb"

    path = File.join(ROOT, "test/dummy/config/database.yml")
    rendered = ERB.new(File.read(path)).result
    loaded = YAML.safe_load(rendered, aliases: true)
    previous = ActiveRecord::Base.configurations
    ActiveRecord::Base.configurations = loaded

    test_config = ActiveRecord::Base.configurations.configs_for(env_name: "test").sole
    development_config = ActiveRecord::Base.configurations.configs_for(env_name: "development").sole

    assert_equal ENV.fetch("TEST_DB_NAME", "recording_studio_notifications_email_test"), test_config.database
    assert_equal ENV.fetch("DB_NAME", "recording_studio_notifications_email_development"), development_config.database
    refute_equal development_config.database, test_config.database
  ensure
    ActiveRecord::Base.configurations = previous if previous
  end
end
