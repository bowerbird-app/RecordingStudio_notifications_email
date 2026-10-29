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
until published releases are available. Current pins include Recording Studio
`v6.3.0` (runtime floor `>= 6.1.0`), Accessible `v0.24.0`, Trashable `v0.12.0`
(`require: false`; query-only for Accessible), notifications `v0.14.1`,
Metrics `v0.7.0`, and FlatPack `v0.1.329`. The dummy also pins Commentable
`v0.7.0`, Root Switchable `v0.11.2`, and Cache `v0.6.0`. Accessible `0.11+`
needs string roles, its 0.8–0.11 migrations, and an
`access_actor_types` allowlist (dummy uses `User`). Accessible `0.14`
adds access constraint/rule tables (dummy installs those migrations);
`0.15` is translation-only; `0.17` filters kept rows via Trashable query
helpers; `0.18` adds `ControllerAuth` for sibling engines (no Accessible
migration). Grants go through
`bootstrap_owner_access!` / `grant_access`. Accessible, Commentable,
notifications, and Root Switchable ship English I18n keys for their own
views; rendered English is unchanged.

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
  individual_mailer: "notification_mailer/individual/page_comment",
  rollup_mailer: "notification_mailer/rollup/page_comment"
)
```

`individual_mailer` and `rollup_mailer` are optional Rails template paths
stored by this gem. Notifications 0.9 rejects unknown register options, so
these two are removed before the parent registry sees the call. Each path
needs matching `.html.erb` and `.text.erb` files. When omitted, the email
channel renders its bundled individual or rollup template.

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

This gem deliberately does not provide inbound email or webhook endpoints.

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
