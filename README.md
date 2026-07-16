# RecordingStudioNotificationsEmail

`recording_studio_notifications_email` is the Action Mailer channel for
[`recording_studio_notifications`](https://github.com/bowerbird-app/RecordingStudio_notifications).
It is a standalone Rails engine under `RecordingStudioNotificationsEmail`.

The gem stores no data, mounts no endpoints, and processes no webhooks. The
parent notifications engine owns persistence, background delivery, retries,
idempotency, preferences, and delivery status.

## Installation

```ruby
gem "recording_studio_notifications_email"
```

```bash
bin/rails generate recording_studio_notifications_email:install
```

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
expiring Rails signed message containing only notification and delivery IDs.
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
