# RecordingStudioNotificationsEmail

`recording_studio_notifications_email` is the Action Mailer channel for
[`recording_studio_notifications`](https://github.com/bowerbird-app/RecordingStudio_notifications).
It is a standalone Rails engine under `RecordingStudioNotificationsEmail`.

The gem stores address suppressions, mounts no endpoints, and does not
receive provider webhooks itself. The parent notifications engine owns
notification records, background delivery, retries, notification idempotency,
preferences, and delivery status. `recording_studio_webhooks` owns the inbound
route, signature check, and event dedupe.

## Installation

Add the email channel alongside `recording_studio_notifications` in the host
Rails application's `Gemfile`:

```ruby
# The core gem owns notification records, delivery preferences, and jobs.
gem "recording_studio_notifications"

# This gem provides the Action Mailer `:email` channel.
gem "recording_studio_notifications_email"
```

Install the bundle, complete the core gem's installation and migrations, then
generate this channel's initializer and suppression migration:

```bash
bundle install
bin/rails generate recording_studio_notifications:install
bin/rails db:migrate
bin/rails generate recording_studio_notifications_email:install
bin/rails generate recording_studio_notifications_email:migrations
bin/rails db:migrate
```

The install generator creates
`config/initializers/recording_studio_notifications_email.rb`; set its required
`config.from` value before delivering mail. The migrations generator copies
the address-suppression table. This channel mounts no routes.

During Rails preparation the engine registers an `:email` channel equivalent to:

```ruby
RecordingStudioNotifications.register_channel(
  :email,
  RecordingStudioNotificationsEmail.adapter
)
```

For local development in this repository, parent gems are sourced from GitHub
tags. Current pins include Recording Studio `v7.3.0` (runtime
`>= 7.1` and `< 8.0`), Accessible `v0.45.1`, Trashable `v1.0.1`
(`require: false`; query-only for Accessible), notifications `v0.20.0`
(runtime `>= 0.20.0` and `< 1.0`), Metrics `v0.9.0`, and FlatPack `v0.1.377`.
The dummy also pins Commentable `v0.12.0`, Root Switchable `v0.16.0`, and
Cache `v0.7.0`. Notifications `v0.19.1` requires API `v1.2.1`, which requires
Logs `v0.8.0` and Moveable `v6.0.0`. Moveable requires Icons `v0.4.0`. Those
gems are GitHub tags because they are not published on RubyGems. Grants go through
`bootstrap_owner_access!` / `grant_access`. The dummy allowlists `User` in
`access_actor_types`. Accessible, Commentable, notifications, and Root
Switchable ship English I18n keys for their own views.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with
the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or
put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted
file; do not generate a per-repo dummy key. Confirm decrypt from the dummy app
with `bin/rails credentials:show`.

## Configuration

```ruby
RecordingStudioNotificationsEmail.configure do |config|
  config.from = Rails.application.credentials.dig(:notifications, :from_email)
  config.reply_to = "support@example.com"

  # Recipients use `recipient.email` by default.
  config.recipients.register(User) { |user| user.notification_email }

  # Optional deterministic Message-ID domain. The local part is a SHA-256
  # digest; identifiers and signed tokens are not exposed.
  config.message_id_domain = "mail.example.com"

  # Reply-by-email. Leave reply_domain blank to keep config.reply_to.
  config.reply_domain = "reply.example.com"
  config.reply_address_expires_in = 30.days
  config.require_inbound_authentication = true
  # Authserv-id written by the ingress on Authentication-Results.
  # An empty list trusts nothing, so inbound authentication fails closed.
  config.inbound_authserv_ids = ["mx.example.com"]
end
```

`config.from` is required at delivery time. It may also be supplied through
`RECORDING_STUDIO_NOTIFICATIONS_EMAIL_FROM`.

The recipient registry synchronizes reads, writes, and resets, so registration
from Rails preparation callbacks is safe. Model-specific recipient resolvers
search the recipient's class ancestry. A resolver may return one address or an
array of addresses.

## Parent notification setup

Enable email on a notification type in the parent engine:

```ruby
RecordingStudioNotifications.register_notification_type(
  :page_comment,
  label: "Page comment",
  default_channels: %i[in_app email],
  available_channels: %i[in_app email],
  scope: :root,
  allowed_cadences: %i[individual daily weekly],
  channel_options: {
    email: {
      individual_mailer: "notification_mailer/individual/page_comment",
      rollup_mailer: "notification_mailer/rollup/page_comment"
    }
  }
)
```

`channel_options[:email]` holds optional Rails template paths. Read them
with `definition.channel_options.dig(:email, :individual_mailer)` and
`:rollup_mailer`. Each path needs matching `.html.erb` and `.text.erb`
files. When a path is omitted, the email channel renders its bundled
individual or rollup template.

Then use the normal parent API:

```ruby
RecordingStudioNotifications.notify(
  notification_type: :page_comment,
  recipient: user,
  notifiable: page,
  title: "New comment",
  body: "A collaborator commented on your page.",
  url: page_url(page)
)
```

The parent `DeliveryJob` already decides between synchronous and asynchronous
work. The email adapter calls `deliver_now` inside that job to avoid nested
jobs and to ensure parent delivery status accurately reflects the SMTP result.
Daily, weekly, and other parent rollups are supported through `deliver_rollup`.

## Templates

The engine includes escaped HTML and plain-text fallback templates for
individual and rollup messages:

- `recording_studio_notifications_email/notification_mailer/notification`
- `recording_studio_notifications_email/notification_mailer/rollup`

Applications can override those engine view paths directly or register a
notification-type-specific template. Custom mailers are supported:

```ruby
config.mailer_class = "MyNotificationsMailer"
```

The class must support Action Mailer's `.with(...)` API and expose
`notification` and `rollup` actions.

## Delivery token references

Every message includes
`X-Recording-Studio-Notification-Reference`. The value is a purpose-scoped,
expiring Rails signed message containing notification and delivery IDs plus a
non-sensitive rollup marker.
The signature provides integrity and expiry checks only; it does not provide
confidentiality and should not be treated as authorization. It does not load
models and is safe to validate at an application boundary:

```ruby
reference = RecordingStudioNotificationsEmail::DeliveryToken.verify(header_value)
reference&.notification_id
reference&.notification_ids
reference&.delivery_ids
```

`notification_ids` and `delivery_ids` are index-aligned for rollups.

Use `verify!` when invalid or expired input should raise
`ActiveSupport::MessageVerifier::InvalidSignature`. References expire after 30
days by default:

```ruby
config.signed_reference_expires_in = 7.days
```

`signed_reference_expires_in` applies only to that header. Reply addresses
use `reply_address_expires_in`.

## Reply by email

A recipient can reply to a notification when that type has a reply handler.
This gem checks the reply and calls `RecordingStudioNotifications.handle_reply`.
It does not read Messages. It does not store the reply body.

The gem mounts no routes. The host turns on Action Mailbox and routes the
reply address.

Set `config.reply_domain` before sending mail for a replyable type. The
Reply-To address is `reply+<code>@<reply_domain>`. The code is lowercase
base32. It contains the delivery id, an expiry, and a truncated HMAC. The
local part is at most 64 characters. The signing key uses the purpose
`recording_studio_notifications_email.reply_address`. That purpose is
separate from the delivery reference token. The reference header, its
format, and `signed_reference_expires_in` stay as they are.

A type with no reply handler keeps `config.reply_to`. A blank `reply_domain`
also keeps `config.reply_to`. A rollup that covers more than one delivery
keeps `config.reply_to`, because one address cannot name every delivery.

When `message_id_domain` is set, every message gets a stable Message-ID.
When `notification.thread_key` is present, the message also sets
In-Reply-To and References to an id derived from a hash of that key. The
raw key is not in the header. A rollup sets those headers only when every
notification in the message has the same key.

List-Unsubscribe headers and the unsubscribe link stay on every message.
A suppressed address is still not mailed. Hard bounces, complaints, and
unsubscribes still suppress that address. A soft bounce does not.

### Host setup

1. Choose Postmark, Mailgun, or Amazon SES. Set `config.action_mailbox.ingress`
   to `:postmark`, `:mailgun`, or `:amazon`. Store the ingress password or
   signing key in the host's credentials. This gem does not ship one.
2. Point MX for `reply_domain` at that provider. Publish the DNS records
   the provider requires, including SPF and DKIM.
3. Install Action Mailbox and Active Storage.

```bash
bin/rails action_mailbox:install
bin/rails active_storage:install
bin/rails db:migrate
```

4. Install the Notifications 0.20 migration. This gem adds no migration.

```bash
bin/rails generate recording_studio_notifications:migrations
bin/rails db:migrate
```

5. Route the reply address from the host.

```ruby
class ApplicationMailbox < ActionMailbox::Base
  routing(/^reply\+/i => "recording_studio_notifications_email/reply")
end
```

The ingress must write Authentication-Results. Set
`config.inbound_authserv_ids` to the authserv-id that ingress writes,
the token before the first semicolon. The parser reads every
Authentication-Results field and trusts only those ids. It accepts a
reply only when a trusted field has `dmarc=pass`. An SPF pass is not
enough, because DMARC is what ties the result to the From domain. A
header the sender adds is ignored. An empty list trusts nothing, so
authentication fails closed. `config.require_inbound_authentication`
defaults to true. Set it to false only when the ingress cannot add
that header.

These settings limit the accepted reply. Defaults are 64 KB for the
body, 10 MB for each attachment, and 10 attachments.

```ruby
config.reply_max_body_bytes = 64 * 1024
config.reply_max_attachment_bytes = 10 * 1024 * 1024
config.reply_max_attachments = 10
```

An accepted reply calls `handle_reply` with `channel: :email` and the
inbound Message-ID as `idempotency_key`. A blank body is rejected only
when the reply also has no attachments. A photo-only reply is filed
with an empty body and its blobs. Those blobs stay stored only when
`handle_reply` returns `ok`. A duplicate, a rejection, a failed handler,
an unrecognized result, an unexpected error, or an upload that fails
after an earlier blob was stored purges the blobs with `purge_later`.

`ok` and `duplicate` finish normally, and Action Mailbox marks that
inbound email delivered. `rejected` finishes normally too. This gem
does not send a bounce or any other reply mail. A `failed` result, or a
result this gem does not recognize, raises
`RecordingStudioNotificationsEmail::ReplyFailedError` after the blobs
are purged. The message is the reason symbol and nothing else. Action
Mailbox then marks the inbound email failed.

`ActionMailbox::RoutingJob` does not retry that failure. The job only
calls `inbound_email.route`, and it declares no `retry_on`. The error
still fails the job, so a queue adapter that retries failed jobs on its
own can run it again. Sidekiq does that unless the host turns retries
off. Re-run a failed reply from the Rails Conductor inbound email page.
Conductor sets the status back to pending and enqueues routing. From a
console:

```ruby
inbound_email = ActionMailbox::InboundEmail.find(id)
inbound_email.pending!
inbound_email.route
```

Notifications rolls the claim back when the handler fails, so the same
Message-ID can be processed again. Action Mailbox later incinerates a
processed inbound email, including one whose status is failed. The
default wait is `config.action_mailbox.incinerate_after` (30 days).
Re-run the reply before that. Auto-replies and bounces are ignored.
Logs include the reason symbol only.

## Webhook integration contract

This gem does not mount inbound webhook routes, verify signatures, or store
inbound events. Register an action with
[`recording_studio_webhooks`](https://github.com/bowerbird-app/RecordingStudio_webhooks)
from the host. The host provider parses the payload, checks the signature, and
puts the correlation header value on the payload as `"reference"`.

```ruby
RecordingStudioNotificationsEmail::Webhooks::ApplyEvent.register!(provider: "postmark")
```

`ApplyEvent` builds a `WebhookEvent` and calls `process_webhook_event!`.
Dedupe stays on the webhooks engine's inbound event. This gem does not keep
an idempotency key of its own.

You can also build the event yourself:

```ruby
event = RecordingStudioNotificationsEmail::WebhookEvent.new(
  provider: :postmark,
  event_type: :opened,
  reference: header_value,
  occurred_at: Time.current,
  external_event_id: "evt_123",
  external_message_id: "msg_123",
  metadata: { "stream" => "outbound" }
)

RecordingStudioNotificationsEmail.process_webhook_event!(event: event)
```

Supported event types are:

- `:delivered`
- `:opened`
- `:clicked`
- `:bounced`
- `:complained`
- `:unsubscribed`

Direct handlers:

- `mark_delivered!`
- `mark_opened!`
- `mark_clicked!`
- `mark_bounced!(provider:, bounce_type:)`
- `mark_complained!(provider:)`
- `mark_unsubscribed!(provider:)`

Delivery updates for one reference run in a single transaction. Hard bounces,
complaints, and unsubscribes first write an address suppression in their own
transaction, using the address resolved from the delivery's recipient. That
row remains if the delivery update raises. A soft bounce still updates the
delivery and does not write a suppression.

### Bounce type

The host maps the provider's bounce field onto `bounce_type` before this gem
sees the event. Put it on the payload as `bounce_type` (or `bounceType`), or
under `metadata` with the same key. `ApplyEvent` copies that value onto
`WebhookEvent`, which stores `:hard` or `:soft` for a bounced event. Only an
explicit hard or permanent value suppresses. A missing, blank, or
unrecognised value is soft, including when `mark_bounced!` omits
`bounce_type:`. The delivery is still updated, and nothing is raised.

| Provider value | Normalised | Suppression |
| --- | --- | --- |
| `hard`, `permanent`, `HardBounce`, `hard-bounce` | `:hard` | reason `bounce` |
| `soft`, `transient`, `temporary`, `temp`, `SoftBounce`, `soft bounce` | `:soft` | none |
| omitted, blank, SES `Undetermined`, or any other value | `:soft` | none |

Postmark `Type` and SES `bounceType` can be passed through. `HardBounce` and
`Permanent` suppress. `SoftBounce`, `Transient`, `Temporary`, and
`Undetermined` do not.

Delivered uses `delivered?` and `mark_delivered!(at:)`. The other events call
the notifications 0.10.0 mutators. A repeat is already applied when the
predicate is true. That release stores the timestamp in delivery metadata
and does not define `email_opened?` and the other predicates, so a present
`email_opened_at` (and the matching keys) counts as already applied.

- Delivered: `delivered?`, `mark_delivered!(at:)`
- Opened: `email_opened?`, `mark_email_opened!(at:)`, metadata `email_opened_at`
- Clicked: `email_clicked?`, `mark_email_clicked!(at:)`, metadata `email_clicked_at`
- Bounced: `email_bounced?`, `mark_email_bounced!(at:)`, metadata `email_bounced_at`
- Complained: `email_complained?`, `mark_email_complained!(at:)`, metadata `email_complained_at`
- Unsubscribed: `email_unsubscribed?`, `mark_email_unsubscribed!(at:)`, metadata `email_unsubscribed_at`

Individual and rollup messages add `List-Unsubscribe` and
`List-Unsubscribe-Post` from
`RecordingStudioNotifications.list_unsubscribe_headers`, and an unsubscribe
link from `RecordingStudioNotifications.unsubscribe_url`, in both HTML and
text. The host `default_url_options` makes that link absolute.

## Address suppression

`recording_studio_notifications_email_suppressions` stores one normalised
mailbox. `Suppression.suppress!` records a bounce, complaint, or unsubscribe.
`Suppression.suppressed?` is true while `lifted_at` is nil.
`Suppression.lift!` sets `lifted_at` and leaves the row in place so a later
`suppress!` can clear it.

Both the individual and rollup adapter paths check the table before
`deliver_now` and raise `SuppressedRecipientError` when the address is
suppressed. The error message does not include the address.

Failures raise typed errors:

- `RecordingStudioNotificationsEmail::InvalidWebhookPayloadError`
- `RecordingStudioNotificationsEmail::UnsupportedWebhookEventError`
- `RecordingStudioNotificationsEmail::SuppressedRecipientError`
- `RecordingStudioNotificationsEmail::DeliveryError`
- `ActiveSupport::MessageVerifier::InvalidSignature`

This gem does not mount webhook endpoints or an inbound email route. Reply-by-email uses the host Action Mailbox route above.

## Event facade

Adapters and templates receive a read-only
`RecordingStudioNotificationsEmail::Event`. It normalizes the parent
notification fields and delegates recordable labels, names, and root
resolution to public `RecordingStudio` APIs. This avoids coupling email
presentation to Recording Studio tables or model internals.

## Cloud Agent boot

Cloud Agent Builds run `.cursor/install.sh`, then `.cursor/fetch-skills.sh`.
The install hook provisions a cold image. On a warm snapshot it skips apt,
ruby-build, db:prepare, and tailwind when Ruby, bundle, and Postgres are
already usable. If `RAILS_MASTER_KEY` is set, `install.sh` writes gitignored
`test/dummy/config/master.key` so dummy credentials decrypt. Fetch-skills
always runs last. `.cursor/start.sh` starts PostgreSQL on each boot. Rebuild
with Draft off to load a new pack. See
[Cursor skills in Cloud Agents](docs/cursor-skills.md) and
[Upgrading](docs/UPGRADING.md).

## Validation

The standard suite is the gem tests, then the dummy app tests. CI runs both
and fails when merged line coverage is below 94%.

```bash
bundle exec rubocop
bundle exec rake test
cd test/dummy && bundle exec rails db:test:prepare && bundle exec rails test
```

The gem requires Ruby 3.3+ and Rails 8.1. Dummy mail uses Action Mailer's
`:test` delivery method. Do not point it at a real mailbox.
