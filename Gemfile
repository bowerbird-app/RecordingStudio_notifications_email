# frozen_string_literal: true

source "https://rubygems.org"

# Specify runtime dependencies in recording_studio_notifications_email.gemspec.
gemspec

# Development sources until parent gems are published on RubyGems.
gem "flat_pack", "~> 0.2", github: "bowerbird-app/flatpack", tag: "v0.2.0"
gem "recording_studio", "~> 7.8", github: "bowerbird-app/RecordingStudio", tag: "v7.8.0"
gem "recording_studio_accessible", "~> 0.58", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.58.0"
gem "recording_studio_api", "~> 1.21", github: "bowerbird-app/RecordingStudio_api", tag: "v1.21.2"
gem "recording_studio_icons", "~> 0.5", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.5.0"
gem "recording_studio_logs", "~> 0.9", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.9.0"
gem "recording_studio_metrics", "~> 0.10", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.10.0"
gem "recording_studio_moveable", "~> 6.1", github: "bowerbird-app/RecordingStudio_moveable", tag: "v6.1.0"
gem "recording_studio_notifications", "~> 0.21",
    github: "bowerbird-app/RecordingStudio_notifications",
    tag: "v0.21.0"
gem "recording_studio_trashable", "~> 1.3",
    github: "bowerbird-app/RecordingStudio_trashable",
    tag: "v1.3.0",
    require: false
gem "redis", "~> 5.3"

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
