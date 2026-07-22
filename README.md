# RecordingStudioNotificationsEmail

`recording_studio_notifications_email` is the Action Mailer channel for
[`recording_studio_notifications`](https://github.com/bowerbird-app/RecordingStudio_notifications).
It is a standalone Rails engine under `RecordingStudioNotificationsEmail`.

The gem stores no data, mounts no endpoints, and processes no webhooks. The
parent notifications engine owns persistence, background delivery, retries,
idempotency, preferences, and delivery status.

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
generate this channel's initializer:

```bash
bundle install
bin/rails generate recording_studio_notifications:install
bin/rails db:migrate
bin/rails generate recording_studio_notifications_email:install
```

The email generator creates
`config/initializers/recording_studio_notifications_email.rb`; set its required
`config.from` value before delivering mail. This channel has no migration or
routes of its own.

No migration or route is required. During Rails preparation the engine
registers an `:email` channel equivalent to:

```ruby
RecordingStudioNotifications.register_channel(
  :email,
  RecordingStudioNotificationsEmail.adapter
)
```

For local development in this repository, parent gems are sourced from GitHub
until published releases are available (`recording_studio` and
`recording_studio_notifications` in `Gemfile`).

## Configuration

```ruby
RecordingStudioNotificationsEmail.configure do |config|
  config.from = Rails.application.credentials.dig(:notifications, :from_email)
  config.reply_to = "support@example.com"

  # Recipients use `recipient.email` by default.
  config.recipients.register(User) { |user| user.notification_email }

  # Both page_comment.html.erb and page_comment.text.erb must exist.
  config.templates.register(:page_comment, "notification_mailer/page_comment")

  # Optional deterministic Message-ID domain. The local part is a SHA-256
  # digest; identifiers and signed tokens are not exposed.
  config.message_id_domain = "mail.example.com"
end
```

`config.from` is required at delivery time. It may also be supplied through
`RECORDING_STUDIO_NOTIFICATIONS_EMAIL_FROM`.

The recipient and template registries synchronize reads, writes, and resets,
so registration from Rails preparation callbacks is safe. Model-specific
recipient resolvers search the recipient's class ancestry. A resolver may
return one address or an array of addresses.

## Parent notification setup

Enable email on a notification type in the parent engine:

```ruby
RecordingStudioNotifications.register_notification_type(
  :page_comment,
  label: "Page comment",
  default_channels: %i[in_app email],
  available_channels: %i[in_app email],
  scope: :root,
  allowed_cadences: %i[individual daily weekly]
)
```

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

## Correlation references

Every message includes
`X-Recording-Studio-Notification-Reference`. The value is a purpose-scoped,
expiring Rails signed message containing notification and delivery IDs plus a
non-sensitive rollup marker.
The signature provides integrity and expiry checks only; it does not provide
confidentiality and should not be treated as authorization. It does not load
models and is safe to validate at an application boundary:

```ruby
reference = RecordingStudioNotificationsEmail::Correlation.verify(header_value)
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

This gem intentionally does not mount inbound webhook routes, but it exposes a
provider-agnostic callback surface so a separate webhook gem (for example,
Postmark) can plug in without adapter rewrites.

Build and ingest normalized webhook events:

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

RecordingStudioNotificationsEmail.ingest_webhook_event!(event: event)
```

Optional provider-specific normalization hook:

```ruby
RecordingStudioNotificationsEmail.configure do |config|
  config.webhook_event_transformer = lambda do |event|
    # Return a WebhookEvent or Hash payload compatible with WebhookEvent.new
    # Example: map provider-specific event naming before callback dispatch
    event
  end
end
```

The transformer must return a valid event payload and cannot return `nil`.

Supported event types are:

- `:delivered`
- `:opened`
- `:clicked`
- `:bounced`
- `:complained`
- `:unsubscribed`

Idempotency convention for webhook ingestion:

- `WebhookEvent#idempotency_key` is always present.
- Default key uses `"#{provider}:#{external_event_id}"` when provider supplies a stable event id.
- Without an external event id, a deterministic synthetic key is generated from provider,
  event type, reference token, external message id, and occurred-at timestamp.
- A webhook gem may pass an explicit `idempotency_key:` when provider semantics require
  a custom dedupe strategy.

If your webhook pipeline prefers explicit handlers, call these directly:

- `mark_delivered_from_reference!`
- `mark_opened_from_reference!`
- `mark_clicked_from_reference!`
- `mark_bounced_from_reference!`
- `mark_complained_from_reference!`
- `mark_unsubscribed_from_reference!`

Preferred delivery callback contract in the parent delivery model:

- Delivered: `delivered?`, `mark_delivered!(at:)`
- Opened: `email_opened?`, `mark_email_opened!(at:)`
- Clicked: `email_clicked?`, `mark_email_clicked!(at:)`
- Bounced: `email_bounced?`, `mark_email_bounced!(at:)`
- Complained: `email_complained?`, `mark_email_complained!(at:)`
- Unsubscribed: `email_unsubscribed?`, `mark_email_unsubscribed!(at:)`

For backward compatibility this gem accepts a small alias set (for example
`opened?`/`mark_opened!`), but new integrations should implement the canonical
`email_*` callback names.

Failures raise typed errors:

- `RecordingStudioNotificationsEmail::InvalidWebhookPayloadError`
- `RecordingStudioNotificationsEmail::UnsupportedWebhookEventError`
- `ActiveSupport::MessageVerifier::InvalidSignature`

This gem deliberately does not provide inbound email or webhook endpoints.

## Event facade

Adapters and templates receive a read-only
`RecordingStudioNotificationsEmail::Event`. It normalizes the parent
notification fields and delegates recordable labels, names, and root
resolution to public `RecordingStudio` APIs. This avoids coupling email
presentation to Recording Studio tables or model internals.

## Validation

The standard suite is:

```bash
bundle exec rake test
```

The gem requires Ruby 3.3+ and Rails 8.1.
