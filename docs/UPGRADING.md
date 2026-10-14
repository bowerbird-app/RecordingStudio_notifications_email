# Upgrading

This email channel still has no migration of its own. Email-as-notice
behavior is unchanged.

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
(query-only; pin `v0.10.0` with `require: false`). No Accessible
migration; prefer `recording_studio_trashable_kept_sql` over
`trashed_at: nil` in host finders when Trashable query is available.

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
