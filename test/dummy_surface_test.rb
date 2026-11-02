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

  def test_docs_and_dummy_copy_drop_template_placeholders
    home = File.read(File.join(ROOT, "test/dummy/app/views/home/index.html.erb"))
    install = File.read(File.join(ROOT, "test/dummy/app/views/docs/install.html.erb"))
    tailwind = File.read(File.join(ROOT, "test/dummy/app/assets/tailwind/application.css"))
    readme = File.read(File.join(ROOT, "README.md"))
    dummy_readme = File.read(File.join(ROOT, "test/dummy/README.md"))
    copilot = File.read(File.join(ROOT, ".github/copilot-instructions.md"))
    database = File.read(File.join(ROOT, "test/dummy/config/database.yml"))

    [home, install, readme, dummy_readme, copilot].each do |text|
      refute_includes text, "Template Demo"
      refute_includes text, "rename_gem"
      refute_includes text, "Put the step"
      refute_includes text, "until published"
    end

    refute_includes home, "No route or migration is required"
    assert_includes home, "recording_studio_notifications_email:migrations"
    assert_includes install, "Webhooks::ApplyEvent.register!"
    refute_includes tailwind, "5ae524ff5c17"
    refute_includes dummy_readme, "source of truth"
    refute_includes dummy_readme, "starter sidebar pages"
    refute_includes copilot, "Do not add migrations, routes, inbound email processing, or webhooks."
    assert_includes copilot, "suppression migration"

    assert_includes database, 'ENV.fetch("DB_NAME") { "recording_studio_notifications_email_development" }'
    assert_includes database, 'ENV.fetch("TEST_DB_NAME") { "recording_studio_notifications_email_test" }'
    refute_includes database, "app_development"
    refute_includes database, "app_test"
    test_database = database[/^test:\n(?:  .*\n)*/]
    assert_includes test_database, "TEST_DB_NAME"
    refute_includes test_database, 'ENV.fetch("DB_NAME")'
  end
end
