# Upgrading

## 0.3.14

This version adds `recording_studio_notifications_email_suppressions`. From
the host application:

```bash
bin/rails generate recording_studio_notifications_email:migrations
bin/rails db:migrate
```

Bounce and complaint callbacks write that table before they update the
delivery. A suppressed address raises `SuppressedRecipientError` from both
adapter paths and is not mailed.

Webhook ingestion no longer computes or stores `WebhookEvent#idempotency_key`.
Dedupe belongs to `recording_studio_webhooks`. Register the action from the
host:

```ruby
RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.register!(provider: "postmark")
```

The host provider still verifies the signature and puts the correlation
header on the payload as `"reference"`. There is no
`webhook_event_transformer`.

Legacy delivery aliases are gone, including `failed?`, `mark_failed!`, and
the opened-to-`read_at` fallback. This gem calls only
`mark_delivered!(at:)` and the canonical `mark_email_*!(at:)` names. Until
`recording_studio_notifications` 0.10.0 adds `mark_email_*!`, the other
event types raise `UnsupportedWebhookEventError`. A bounce or complaint
still records the suppression before that error.

`process_webhook_event!` is not idempotent on its own. Replaying it outside
the webhooks engine applies the event again when the delivery predicate is
still false.

Unsubscribe events write a suppression with reason `unsubscribed`, in the
same transaction split as bounce and complaint. Hard bounces suppress with
reason `bounce`. Soft or transient bounces do not. Put the provider's bounce
class on the payload as `bounce_type` (or `metadata.bounce_type`). Accepted
hard values are `hard`, `permanent`, `HardBounce`, and `hard-bounce`. Accepted
soft values are `soft`, `transient`, `temporary`, `temp`, `SoftBounce`, and
`soft bounce`. A blank type is hard. Any other value, including SES
`Undetermined`, raises `InvalidWebhookPayloadError`; map it in the host.

Development pins for this version are notifications `v0.9.0`, metrics
`v0.3.1` (`>= 0.3`, `< 0.4`), root_switchable `v0.9.4`, and trashable
`v0.11.1`. Notifications 0.9 and root_switchable 0.9.4 need that metrics
range. Trashable `v0.11.0` still requires metrics `~> 0.2`, so it cannot
resolve beside them. None of those pin bumps adds a migration.

Notifications 0.9 rejects unknown `register` options. Keep passing
`individual_mailer:` and `rollup_mailer:` to `register_notification_type`.
This gem records those paths and does not forward them. `notify` with no
selected channels now returns `nil` instead of raising. Hosts that never
defined an Accessible `:view` action get a default one from notifications.

When the dummy (or a host) follows the current development pins, Accessible
`0.11` stores roles as strings. Run Accessible's migrations
(`bin/rails generate recording_studio_accessible:migrations` then
`bin/rails db:migrate`), set `access_actor_types`, and grant access through
`bootstrap_owner_access!` / `grant_access`. Do not write
`RecordingStudio::Access` rows directly.

Accessible `0.14` adds `recording_studio_access_constraints` and
`recording_studio_access_rules` (install via the same generator). Existing
apps do nothing until they set `config.action_audiences` and enable
`:action_audiences` on the types that should hold rules. Accessible
`0.15` is translation-only (i18n wave 2); no migration; English hosts
need no change. Accessible `0.17` depends on Trashable `~> 0.10`
(query-only; pin with `require: false`). Trashable `0.11` requires
Recording Studio `~> 4.7` (development pins `v0.11.1` and `v4.7.0`).
Accessible `0.18`
adds `ControllerAuth` for sibling engines; no Accessible migration.
Prefer `recording_studio_trashable_kept_sql` over `trashed_at: nil` in
host finders when Trashable query is available.

Root Switchable `0.8.0` (i18n wave 2 for `page_copy`) needs Metrics `~> 0.2`
(dummy pins `v0.2.0`). Root Switchable `0.9.0` switches rate limiting to
`RecordingStudioCache::RateLimiter` and needs Cache `~> 0.5` (dummy pins
`v0.5.0`). No host migrations for Root Switchable `0.7.0`/`0.8.0`/`0.9.0`.

Commentable `0.5.0` is translation-only (i18n wave 2 for flashes, errors, and
display labels). No migration; English hosts need no change.

Notifications `0.6.0` adds a runtime dependency on Metrics `~> 0.2` (no
migration). Notifications `0.7.0` is translation-only (i18n wave 2 for
flashes, badge overflow, and Admin chrome defaults); no migration; English
hosts need no change.

Recording Studio `4.5.0` makes `Labels.empty_label` I18n-resolved (English
unchanged). Recording Studio `4.6.0` adds English fallback for shipped
`recording_studio.*` keys via `RecordingStudio.t` when the active locale
has no translation. No host migration for either. Prefer
`Labels.empty_label` over identity checks against `Labels::EMPTY_LABEL`
when the locale may not be English.

## 0.3.1

Rebuild the Cloud Agent environment with Draft off so Build loads the skill
pack. See [Cursor skills in Cloud Agents](docs/cursor-skills.md).
