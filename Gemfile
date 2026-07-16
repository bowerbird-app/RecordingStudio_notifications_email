# frozen_string_literal: true

source "https://rubygems.org"

# Specify runtime dependencies in recording_studio_notifications_email.gemspec.
gemspec

# Development sources until parent gems are published on RubyGems.
gem "recording_studio_notifications",
    github: "bowerbird-app/RecordingStudio_notifications",
    branch: "copilot/create-recording-studio-notifications"
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.125"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "recording_studio/v3.0.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "0.3.1"

group :development, :test do
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
