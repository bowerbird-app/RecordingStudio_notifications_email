# Upgrading

This email channel still has no migration of its own. Email-as-notice
behavior is unchanged.

When the dummy (or a host) follows the current development pins, Accessible
`0.11` stores roles as strings. Run Accessible's migrations
(`bin/rails generate recording_studio_accessible:migrations` then
`bin/rails db:migrate`), set `access_actor_types`, and grant access through
`bootstrap_owner_access!` / `grant_access`. Do not write
`RecordingStudio::Access` rows directly.

Root Switchable `0.8.0` (i18n wave 2 for `page_copy`) needs Metrics `~> 0.2`
(dummy pins `v0.2.0`). No host migrations for Root Switchable `0.7.0`/`0.8.0`.

## 0.3.1

Rebuild the Cloud Agent environment with Draft off so Build loads the skill
pack. See [Cursor skills in Cloud Agents](docs/cursor-skills.md).
