# Dummy App

This Rails app is the host sandbox for the email notification channel.

## What It Covers

- Devise authentication with a seeded admin user
- `Current.actor` wiring for Recording Studio events
- Root workspace plus seeded folder and page recordables
- FlatPack layout integration and Tailwind source scanning
- Mounted `RecordingStudio::Engine` route behavior inside a host app
- A starter sidebar menu and companion docs pages for gem-specific onboarding

## Quick Start

Dummy credentials (`config/credentials.yml.enc`) use the shared RecordingStudio_*
development master key. Set `RAILS_MASTER_KEY` or write that value to
`config/master.key` (gitignored). Do not mint a per-repo dummy key.

```bash
cd test/dummy
bundle install
bin/rails credentials:show
bin/rails db:setup
bin/dev
```

Run the commands above from the dummy app directory, not the repository root.

Then open the app and sign in with:

- Email: `admin@admin.com`
- Password: `Password`

## Useful Routes

- `/` - create a page and send mail
- `/recording_studio` - redirects to `/` while the mounted Recording Studio engine stays available under that prefix for non-root routes
- `/users/sign_in` - Devise sign-in page
- `/docs/install` - host install steps
- `/docs/config` - channel configuration
- `/docs/webhook_lab` - create a notification and apply a provider event
- `/docs/recordable_types`, `/docs/recordings_tree`, `/docs/gem_views`, `/docs/methods` - host wiring notes
- `/pages` - pages in the signed-in workspace
- `/system_notifications/new` - send a system notice
- `/up` - Rails health check

## Why This App Exists

Use this app to exercise host wiring: sign-in, page mail, suppressions, and the webhook lab. The gem suite under `test/` covers the channel library. Both suites run in CI.

The signed-in layout is `app/views/layouts/flat_pack_sidebar.html.erb`. The home page stays a short demo. Longer notes live on the docs pages.
