# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.3.15] - 2026-10-17

### Changed

- Pin `recording_studio_notifications` to `v0.10.0`. The runtime dependency is
  now `>= 0.10.0, < 1`. Metrics stays `>= 0.3, < 0.4`; 0.10.0 does not
  require another pin bump.
- Opened, clicked, bounced, complained, and unsubscribed callbacks call
  `Delivery#mark_email_*!(at:)`. A repeated event is already applied when the
  delivery predicate is true, or when that method's metadata timestamp is
  already set. Those events no longer raise `UnsupportedWebhookEventError`.
- Hard bounces, complaints, and unsubscribes still write the address
  suppression in their own transaction first. Soft, missing, and unknown
  bounce types still update the delivery and do not suppress.
- Individual and rollup mail includes `List-Unsubscribe` and
  `List-Unsubscribe-Post` from `RecordingStudioNotifications.list_unsubscribe_headers`,
  and an unsubscribe link from `RecordingStudioNotifications.unsubscribe_url`,
  in the HTML and text templates.

### Upgrade notes

- Bump notifications to `v0.10.0` and run
  `bin/rails generate recording_studio_notifications:migrations` then
  `bin/rails db:migrate`. That migration adds `inbox`.
- Set `default_url_options` so the unsubscribe link is absolute.
- See [Upgrading](docs/UPGRADING.md).

## [0.3.14] - 2026-10-16

### Added

- `recording_studio_notifications_email_suppressions` stores one normalised
  address, a bounce, complaint, or unsubscribe reason, the provider, and `lifted_at`.
  `Suppression.suppress!`, `suppressed?`, and `lift!` are the public API.
- `bin/rails generate recording_studio_notifications_email:migrations` copies
  that migration into the host. The dummy app includes it.
- `Webhooks::ApplyEvent.register!(provider:)` registers a
  `recording_studio_webhooks` action that calls `process_webhook_event!`.
- Both adapter paths raise `SuppressedRecipientError` before `deliver_now`
  when the resolved address is suppressed.
- CI runs the dummy app tests against PostgreSQL and fails when merged line
  coverage is below 94%.

### Changed

- Rollup delivery updates (`mark_delivered!` and the webhook loop) run in one
  transaction.
- Hard bounces, complaints, and unsubscribes write the suppression in their
  own transaction first, then update deliveries. The address comes from the
  delivery's recipient. Only explicit hard or permanent bounce values
  suppress. A missing, blank, or unrecognised type, including SES
  `Undetermined`, is soft: the delivery is updated, no suppression is
  written, and no error is raised. `bounce_type` is normalised from the
  payload.
- Development pins: notifications `v0.9.0`, metrics `v0.3.1`
  (`>= 0.3`, `< 0.4`), root_switchable `v0.9.4`, and trashable `v0.11.1`
  so the metrics floor resolves.
- `individual_mailer` and `rollup_mailer` stay on this gem's registration
  wrapper. Notifications 0.9 rejects unknown register options, so a catch-all
  `**options` is no longer treated as support for those paths.
- Webhook callbacks call only `mark_delivered!(at:)` and `mark_email_*!(at:)`.
  Missing canonical methods raise `UnsupportedWebhookEventError`.
- `WebhookEvent` no longer builds an idempotency key. Inbound dedupe stays in
  `recording_studio_webhooks`.

### Removed

- Legacy delivery aliases, including `failed?` / `mark_failed!` and the
  opened-to-`read_at` fallback.
- The undocumented `webhook_event_transformer` configuration, which had no
  implementation.
- Committed `coverage/` directories. They are gitignored.

### Upgrade notes

- Run `bin/rails generate recording_studio_notifications_email:migrations`
  and `bin/rails db:migrate`.
- Register `Webhooks::ApplyEvent` with `recording_studio_webhooks` from the
  host. Do not add an inbound-event table, signature verifier, or route in
  this gem.
- Opened, clicked, bounced, complained, and unsubscribed callbacks require
  `recording_studio_notifications` 0.10.0 `mark_email_*!` methods. Until then
  they raise `UnsupportedWebhookEventError`. Explicit hard bounces,
  complaints, and unsubscribes still suppress the address. Map the provider
  bounce field onto `bounce_type` as described in the README. A missing,
  blank, or unknown type is a soft bounce and does not suppress.
- Pin notifications `v0.9.0`, metrics `>= 0.3, < 0.4` (tag `v0.3.1`), and
  root_switchable `v0.9.4`. Trashable moves to `v0.11.1` because `v0.11.0`
  still requires metrics `~> 0.2`. No new migration for those gems.
- See [Upgrading](docs/UPGRADING.md).

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/compare/v0.3.15...HEAD
[0.3.15]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/compare/v0.3.14...v0.3.15
[0.3.14]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/compare/v0.3.1...v0.3.14
[0.3.1]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.3.1
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.3.0
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_notifications_email/releases/tag/v0.1.0
