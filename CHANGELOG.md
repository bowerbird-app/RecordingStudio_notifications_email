# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.2.0] - 2026-09-01

### Changed

- Require RecordingStudio `~> 4.2` (tested against `4.2.0`).
- Development and dummy pins: RecordingStudio `v4.2.0`, RecordingStudioAccessible
  `v0.7.0`, RecordingStudioRootSwitchable `v0.5.0`, RecordingStudioCommentable
  `v0.3.0`.

### Upgrade notes

- Upgrade RecordingStudio to `4.2.0` or newer before installing this gem
  version. Hosts still on RecordingStudio 3.x must upgrade core first.
- Run the RecordingStudio harden migration if you have not already
  (`rails g recording_studio:migrations` then `rails db:migrate`).
- Companion dummy pins should move with core: Accessible `0.7.0+`, Root
  Switchable `0.5.0+`, and Commentable `0.3.0+` when those addons are used.
- No migration is required for this email channel gem itself.

## [0.1.0] - 2026-07-16

### Added

- Standalone `RecordingStudioNotificationsEmail` Rails engine.
- Thread-safe template and recipient resolver registries.
- Action Mailer channel registration with individual and rollup delivery.
- HTML and text fallback templates.
- Expiring signed correlation references.
- Recording Studio-backed normalized event facade.

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.1.0
