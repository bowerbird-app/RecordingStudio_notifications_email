# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.3.1] - 2026-09-02

Cloud Agent Builds now boot like Billing 0.9.13. Email-as-notice behavior is
unchanged.

### Added

- Tracked Cloud Agent boot files: `.cursor/environment.json` runs
  `.cursor/install.sh`. `.cursor/start.sh` starts PostgreSQL on each boot.
- `.cursor/install.sh` provisions a cold image. On a warm snapshot it skips
  apt, ruby-build, db:prepare, and tailwind when Ruby, bundle, and Postgres
  are already usable. A skippable provision failure does not fail the Build.
  Fetch-skills always runs last, not `|| true`.
- `.cursor/fetch-skills.sh` loads the skill pack into gitignored
  `.cursor/skills/` and `.cursor/rules/`. Those directories are not vendored
  and are not packaged in the gem.

### Upgrade notes

- No host or schema changes. Rebuild the Cloud Agent environment with Draft
  off so Build loads the pack. See [Upgrading](docs/UPGRADING.md).

## [0.3.0] - 2026-09-01

### Changed

- `Event` uses `delivery_payload_for` when a delivery is present.
- Require `recording_studio_notifications` `>= 0.3.0`.

### Upgrade notes

- Install `recording_studio_notifications` `0.3.0` first.

## [0.2.0] - 2026-09-01

### Changed

- Require RecordingStudio `~> 4.2` (tested against `4.2.0`).
- Development and dummy pins: RecordingStudio `v4.2.0`, RecordingStudioAccessible
  `v0.7.0`, RecordingStudioRootSwitchable `v0.5.0`, RecordingStudioCommentable
  `v0.3.0`.
- Unit tests load `minitest/mock` and pass hash sources into `Event.new`.

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.3.1
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.3.0
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.1.0
