# Upgrading

## 0.7.0

Development and dummy apps pin Recording Studio `~> 7.8` (`v7.8.0`),
FlatPack `~> 0.2` (`v0.2.0`), Accessible `~> 0.58` (`v0.58.0`), API
`~> 1.21` (`v1.21.2`), Icons `~> 0.5` (`v0.5.0`), Logs `~> 0.9`
(`v0.9.0`), Metrics `~> 0.10` (`v0.10.0`), Moveable `~> 6.1` (`v6.1.0`),
Notifications `~> 0.21` (`v0.21.0`), and Trashable `~> 1.3` (`v1.3.0`).
The dummy also pins Cache `~> 0.8` (`v0.8.0`) and Root Switchable
`~> 0.17` (`v0.17.0`). Commentable stays `v0.12.0`.

Hosts MUST run the Recording Studio 7.4, 7.5, and 7.7 migrations if they
have not. This gem adds no migration. Gemspec floors stay Recording Studio
`>= 7.1`, `< 8.0` and Notifications `>= 0.20.0`, `< 1.0`.

flat_pack 0.2.0 is supported; hosts moving to 0.2 must remove the manual
`flat_pack/heroicons` importmap pin and any `flat-pack--icon` controller
registration. The dummy drops that pin. Icons render on the server.

API 1.12 and newer raise on boot when `config/recording_studio_api.yml` is
missing. Notifications 0.21 depends on API. Add that file if the host does
not have one. The dummy sets `timeout: 5`.

## 0.6.0

This gem requires Recording Studio `>= 7.1`, `< 8.0` and Notifications
`>= 0.20.0`, `< 1.0`.

Reply-by-email is optional. Leave `config.reply_domain` unset and the
previous Reply-To behavior stays. A notification type accepts replies only
after the host registers a reply handler with Notifications.

This gem adds no migration. Hosts that accept replies need three sets of
migrations.

1. Notifications 0.20 adds `thread_key` and the replies table. Run
   `bin/rails generate recording_studio_notifications:migrations`, then
   `bin/rails db:migrate`.
2. Action Mailbox. Run `bin/rails action_mailbox:install`, then migrate.
3. Active Storage, for reply attachments. Run
   `bin/rails active_storage:install`, then migrate.

Choose Postmark, Mailgun, or Amazon SES as the Action Mailbox ingress.
Point MX for `reply_domain` at that provider and publish the DNS records
it requires. Put the ingress secret in the host's credentials.

Route replies from the host. This gem mounts no route.

```ruby
class ApplicationMailbox < ActionMailbox::Base
  routing(/^reply\+/i => "recording_studio_notifications_email/reply")
end
```

New settings are `reply_domain`, `reply_address_expires_in` (default 30
days), `require_inbound_authentication` (default true),
`inbound_authserv_ids` (default empty), `reply_max_body_bytes`,
`reply_max_attachment_bytes`, and `reply_max_attachments`. Threading
headers use the existing `message_id_domain`.

Set `inbound_authserv_ids` to the authserv-id on the
Authentication-Results header the ingress adds. Only those fields are
trusted, and a reply needs `dmarc=pass` on one of them. SPF alone is
not accepted. Leave the list empty and, while authentication is
required, every reply is rejected.

`DeliveryToken` is unchanged. Its purpose, header, format, and
`signed_reference_expires_in` are separate from the reply address.

A reply that Notifications rejects is ignored. This gem does not bounce
it and does not send mail back. A duplicate is processed. A failed
handler, or a result this gem does not recognize, raises
`RecordingStudioNotificationsEmail::ReplyFailedError`. The message is
the reason symbol only. Action Mailbox marks that inbound email failed.
`ActionMailbox::RoutingJob` does not declare `retry_on`, so Action
Mailbox does not schedule another attempt. A queue adapter that retries
failed jobs on its own, such as Sidekiq, still can. Re-run the reply
from the Rails Conductor inbound email page, or in a console with
`inbound_email.pending!` and `inbound_email.route`, before incineration
(30 days by default). Notifications rolls a failed handler's claim back,
so the same Message-ID can be tried again.

Suppressed addresses still do not receive mail. Hard bounces, complaints,
and unsubscribes still suppress. Soft bounces do not. Every message still
includes List-Unsubscribe headers and an unsubscribe link.

The gem loads when Action Mailbox is not enabled. Require the mailbox only
by routing to it, which the engine does when Action Mailbox is loaded.

## 0.5.4

This gem requires Recording Studio `>= 7.0`, `< 8.0` and Notifications
`>= 0.18.0`, `< 1.0`.

`root_recording_for` only finds a root. Create one with
`RecordingStudio.create_root_recording!(recordable, actor:)`. Set
`config.authorize_write` and pass an actor. A new root is authorized with
`root_recording` nil. Do not set `allow_unauthorized_writes`.

Recording Studio 7 stores `root_recording_id` on events. Run core migration
`add_root_recording_id_to_recording_studio_events` if that column is missing.
This gem adds no migration of its own.

Repository pins: Recording Studio `v7.0.0`, Notifications `v0.18.0`,
Accessible `v0.44.0`, Trashable `v0.17.0`, Metrics `v0.9.0`, and dummy Root
Switchable `v0.16.0`. Commentable stays `v0.8.0`, Cache stays `v0.6.3`, and
FlatPack stays `v0.1.356`. The dummy lock updates `msgpack` to `1.8.7` and
`puma` to `8.1.0`. No application change for those two.

## 0.5.2

Development pins only. Core, Accessible, and notifications tags are
unchanged. `view_component` stays `4.20.0`. There is no migration.

## 0.5.1

Root CI runs a Security job: Brakeman and `bundler-audit check --update`
on this gem and on `test/dummy`. The development bundle includes
`brakeman` and `bundler-audit` for that job. Checkout and Ruby setup
are pinned by commit. The org token is set only on the steps that
install gems.

No application change. `view_component` stays `4.20.0`. There is no migration.

## 0.5.0

Email template paths are no longer stored on this gem. Pass them in
notifications `channel_options` when you register the type. `:email` must
be an available channel.

```ruby
RecordingStudioNotifications.register_notification_type(
  :page_comment,
  label: "Page comment",
  available_channels: %i[in_app email],
  channel_options: {
    email: {
      individual_mailer: "notification_mailer/individual/page_comment",
      rollup_mailer: "notification_mailer/rollup/page_comment"
    }
  }
)
```

Read a path with `definition.channel_options.dig(:email, :individual_mailer)`
or `:rollup_mailer`. This gem no longer accepts `individual_mailer:` or
`rollup_mailer:` as register keywords, and
`RecordingStudioNotificationsEmail.notification_type_mailers` is gone.

The adapter constant is `RecordingStudioNotificationsEmail::ActionMailerAdapter`.
`RecordingStudioNotificationsEmail::Adapters::ActionMailerAdapter` and
`RecordingStudioNotificationsEmail::Channels::ActionMailerAdapter` are gone.

### Breaking

`tracked_notification_path` is now the absolute URL from
`RecordingStudioNotifications.notification_url`. `deliver` raises
`ArgumentError` when that host is missing, instead of leaving the path
off.

Move a host that already sends mail:

1. Set `config.action_mailer.default_url_options` to include `:host`
   (and `:protocol` when the link should be https). Unsubscribe links
   already use those options.
2. Custom mailers that treated `tracked_notification_path` as a relative
   path should put the absolute URL in the href. Do not add a host in
   front of it.
3. A missing open route still leaves the path off. A blank host raises
   `ArgumentError` during `deliver`.

`view_component` stays `4.20.0`. There is no migration.

## 0.4.7

Notifications must be `>= 0.14.7` and `< 1`. This repository pins tag
`v0.14.7`.

Replayed email events use `Delivery#email_event_applied?`. Read the time
with `Delivery#email_event_at`. This gem no longer looks for
`email_opened_at` and the other timestamp keys on its own.

Individual mail still passes the notifications open path as
`tracked_notification_path` (`open_notification_path`). The path is
left off when that helper is missing or the route cannot be built.
Other errors propagate. This patch does not switch the link to an
absolute URL.

`Event#url` asks `RecordingStudioNotifications::UrlSafety` and does not
pre-check control characters or backslashes. `UrlSafety` rejects those.

The dummy inbox sets `config.default_inbox_scope = "current_root"`. Hosts
that copied an inbox scope patch should delete it and set that config.
`"all"` lists every workspace. `"current_root"` stays on the workspace
the person is in.

`view_component` stays `4.20.0`. There is no migration.

## 0.4.6

The gem now requires `recording_studio` `>= 6.1.0` and `< 7`, and
`recording_studio_notifications` `>= 0.14.0` and `< 1`.

Repository pins: FlatPack `v0.1.332`, Root Switchable `v0.11.3`. Core stays
`v6.3.0`. Notifications in that release stayed `v0.14.1`. See 0.4.7 for
the current notifications pin. `view_component` stays `4.20.0`.

## 0.4.5

The dummy app resolves its layout only through `recording_studio_layout`.
Signed-in screens use `flat_pack_sidebar`. Devise uses `application`.
The old `layout :application_layout` override is gone.

Page forms use FlatPack select fields. The workspace outline lists pages
and folders in the current workspace. Private Workspace is seeded with
the Private Notes folder and the Private Start page. Studio Workspace
still has Product Docs and Getting Started. `individual_mailer` and
`rollup_mailer` in the config sample are deprecated and go away in
[0.5.0](#050), replaced by notifications `0.14.3` `channel_options`.

The dummy Tailwind file also scans gems installed under
`/usr/local/lib/ruby/gems`. Rebuild styles with `bin/rails tailwindcss:build`
after pulling this version.

## 0.4.4

The dummy app no longer overrides the notifications inbox. The inbox lists
the current workspace. When notifications releases `config.default_inbox_scope`,
a later version of this gem can offer every workspace from that setting.
There is no public way to do that on notifications `0.14.1`.

Workspace switching uses Accessible. A person only sees workspaces they can
open. Creating a page checks `authorized?` for `:edit` on that workspace
before anything is saved. Sending a system notice checks `:admin` on the
current workspace, and it is sent only to people who can open that
workspace.

## 0.4.3

`config/recording_studio_notifications_email.yml` is optional. A missing file
boots as before. Invalid YAML, or a file whose environment section is not a
hash, raises `RecordingStudioNotificationsEmail::ConfigurationError` during
engine load. Previously that failure was logged and ignored.

The link path inside a message still uses the notifications open route. If
that helper is not mounted, the message falls back to the event URL. Other
errors while building the path are no longer swallowed.

## 0.4.2

`Event#url` always uses `RecordingStudioNotifications::UrlSafety.safe?`.
The previous local fallback is gone. On notifications `0.10.0` or newer that
fallback never ran, so absolute links still need `allowed_url_hosts` on the
notifications configuration. Control characters and backslashes are still
rejected before the parent check.

## 0.4.0

This version requires Recording Studio `>= 6.1.0`. From a host Gemfile that
still pins core from GitHub:

```ruby
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.3.0"
```

Stay on `0.3.15` until the host is on Recording Studio 6.1 or newer. There is
no migration in this gem.

Pins shipped with 0.4.0: core `v6.3.0`, FlatPack `v0.1.329`, notifications
`v0.14.1`, Commentable `v0.7.0`, Accessible `v0.24.0`, Trashable `v0.12.0`,
Metrics `v0.7.0`, Cache `v0.6.0`, Root Switchable `v0.11.2`. See 0.4.6 for
the current FlatPack and Root Switchable pins. Root Switchable
`config.layout` must be a layout name,
`nil`, `false`, or a callable invoked as `call(controller:)` — not a method
Symbol.

## 0.3.15

This version requires `recording_studio_notifications` `0.10.0`. From the
host application:

```bash
bin/rails generate recording_studio_notifications:migrations
bin/rails db:migrate
```

The notifications migration adds `inbox` (boolean, null false, default
true). Existing rows stay in the inbox. Metrics stays `>= 0.3, < 0.4`.
Notifications 0.10.0 does not require another dependency pin.

Opened, clicked, bounced, complained, and unsubscribed callbacks call
`Delivery#mark_email_opened!`, `mark_email_clicked!`, `mark_email_bounced!`,
`mark_email_complained!`, and `mark_email_unsubscribed!`. They no longer
raise `UnsupportedWebhookEventError` when those methods exist. A second
event for the same delivery is already applied when the matching predicate
is true. Notifications 0.10.0 does not define `email_opened?` and the other
predicates; it stores `email_opened_at` and the matching keys in delivery
metadata, and this gem treats a present timestamp as already applied.
`mark_email_unsubscribed!` also turns that type's email preference off. A
bounce still does not change delivery status.

Hard bounces, complaints, and unsubscribes still write the address
suppression in their own transaction before the delivery update. A missing,
blank, or unknown bounce type, including SES `Undetermined`, stays soft.

Mail uses `RecordingStudioNotifications.list_unsubscribe_headers` for
`List-Unsubscribe` and `List-Unsubscribe-Post`, and
`RecordingStudioNotifications.unsubscribe_url` for the link in the HTML and
text templates, including rollups. Set the host `default_url_options` (the
same host mailers already use) so that link is absolute. This gem does not
sign its own unsubscribe token.

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
event types raise `UnsupportedWebhookEventError`. An explicit hard bounce,
a complaint, or an unsubscribe still records the suppression before that
error. A bounce without an explicit hard or permanent type does not.

`process_webhook_event!` is not idempotent on its own. Replaying it outside
the webhooks engine applies the event again when the delivery predicate is
still false.

Unsubscribe events write a suppression with reason `unsubscribed`, in the
same transaction split as bounce and complaint. Only an explicit hard or
permanent bounce suppresses, with reason `bounce`. Put the provider's bounce
class on the payload as `bounce_type` (or `metadata.bounce_type`). Hard
values are `hard`, `permanent`, `HardBounce`, and `hard-bounce`. Everything
else is soft and writes no suppression, including a missing or blank type,
`soft`, `transient`, `temporary`, `temp`, `SoftBounce`, `soft bounce`, and
SES `Undetermined`. The delivery is still updated, and the unknown value
raises no error.

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
