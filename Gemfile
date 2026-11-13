# frozen_string_literal: true

source "https://rubygems.org"

# Specify runtime dependencies in recording_studio_notifications_email.gemspec.
gemspec

# Development sources until parent gems are published on RubyGems.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.356"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.7.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.32.0"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.8.0"
gem "recording_studio_notifications",
    github: "bowerbird-app/RecordingStudio_notifications",
    tag: "v0.15.0"
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.14.0", require: false

group :development, :test do
  gem "debug"
  gem "minitest-mock"
  gem "simplecov", require: false
end

group :development do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
