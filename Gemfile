# frozen_string_literal: true

source "https://rubygems.org"

# Specify runtime dependencies in recording_studio_notifications_email.gemspec.
gemspec

# Development sources until parent gems are published on RubyGems.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.198"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.2.2"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.11.1"
gem "recording_studio_notifications",
    github: "bowerbird-app/RecordingStudio_notifications",
    tag: "v0.3.4"

group :development, :test do
  gem "debug"
  gem "minitest-mock"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
