# README

This README would normally document whatever steps are necessary to get the
application up and running.

## Requirements

* Ruby 3.3.4
* PostgreSQL 12+ (the application's only supported database)

## Database setup

The application uses **PostgreSQL** in all environments. No other database is
supported.

### Configuration

Database connection settings are read from environment variables:

| Variable            | Default                         | Description                          |
|---------------------|---------------------------------|--------------------------------------|
| `DATABASE_URL`      | –                               | Optional full connection URL. When set, it overrides everything below |
| `DATABASE_HOST`     | `127.0.0.1`                     | Database host                        |
| `DATABASE_PORT`     | `5432`                          | Database port                        |
| `DATABASE_USERNAME` | current OS user (`USER`)        | Database role                        |
| `DATABASE_PASSWORD` | (empty)                         | Database password                    |
| `DATABASE_NAME`     | `expense_tracker_production`    | Production database name             |

Example using a connection URL:

```sh
export DATABASE_URL="postgres://myuser:mypassword@localhost:5432/expense_tracker_development"
```

### Create and initialize a fresh database

```sh
bin/rails db:setup
```

`db:setup` creates the database, runs all migrations, and loads the seed data
required for a fresh installation (default expense and income categories).

Existing databases can be migrated and seeded individually:

```sh
bin/rails db:migrate   # run pending migrations
bin/rails db:seed      # load default categories (idempotent, safe to re-run)
```

To fully reset a database:

```sh
bin/rails db:reset     # drop, create, migrate, and seed
```

### Running the test suite

```sh
bin/rails test
```

The test suite runs against the PostgreSQL `test` database and is recreated
automatically between runs.

### Background jobs

Jobs (e.g., the Gmail recurring sync) run through [Solid
Queue](https://github.com/rails/solid_queue) using the primary database. Start
a worker with:

```sh
bin/rails solid_queue:start
```

### Inbound email

`POST /webhooks/email` receives inbound email through a provider-neutral
`MailInboundService`. The selected provider validates the signature, persists a
`MailInboundDelivery`, and enqueues `MailInboundHandleJob`. That job normalizes
the email and enqueues `MailInboundProcessJob`, which reuses the existing expense
import pipeline.

```sh
export MAIL_INBOUND_PROVIDER="cloudflare" # or resend
export INBOUND_EMAIL_RECIPIENT="receive@samyreplies.com"
export INBOUND_EMAIL_USER_EMAIL="your-user@example.com"
export INBOUND_EMAIL_USER_MAP="user1=your-user@example.com"
```

Cloudflare additionally needs `INBOUND_EMAIL_SECRET`; Resend needs
`RESEND_WEBHOOK_SECRET` and `RESEND_API_KEY`.

`INBOUND_EMAIL_RECIPIENT` is the base address. With Cloudflare subaddressing
enabled, any `receive+<token>@samyreplies.com` is accepted. If
`INBOUND_EMAIL_USER_MAP` is present, `<token>` selects the user; for example,
`receive+user1@samyreplies.com` maps through `user1=your-user@example.com`.
If no map is configured, all tokens use `INBOUND_EMAIL_USER_EMAIL`.

Full setup, deployment, local testing and limitations are documented in
[docs/mail_inbound.md](docs/mail_inbound.md).

### Contact form email

The public Contáctanos page (`/contact`) delivers messages through
`ContactMailer`. Configure the internal inbox and sender with:

```sh
export CONTACT_EMAIL="hola@yogasto.co"
export CONTACT_FROM_EMAIL="no-reply@yogasto.co"
```

Both values are optional; those are the defaults. Delivery uses
`deliver_later`, so run the Solid Queue worker in environments that process
background jobs. The form includes a honeypot, per-IP rate limiting and a short
deduplication window; it does not use a CAPTCHA. The internal recipient is never
rendered on the public page.

### Email previews in development

Development captures outgoing mail with `letter_opener` in `tmp/letter_opener`.
Open the web inbox at:

```text
http://localhost:3000/letter_opener
```

The web inbox works even when the server cannot launch a desktop browser
automatically.

When deploying new pages from `app/theme/theme.yml`, create only the missing
Maglev pages without overwriting edited content:

```sh
bin/rails yogasto:sync_cms_pages
```

### Help center

The public help center lives at `/ayuda` and is administered from Maglev. The
initial categories, articles, navigation link and derived search/rating data can
be prepared with:

```sh
bin/rails yogasto:setup_help_center
```

Editorial rules, page paths, section names and reindexing commands are documented
in [docs/help_center.md](docs/help_center.md).

### Privacy policy

The public privacy policy lives at `/privacidad` and is administered from
Maglev. It is published with `index,follow` and contains only user-facing,
verified copy. Internal verification notes and pending legal decisions are
documented in [docs/privacy_policy_audit.md](docs/privacy_policy_audit.md);
editorial instructions and publishing steps are in
[docs/privacy_policy.md](docs/privacy_policy.md).

### Terms and conditions

The terms page lives at `/terminos-y-condiciones` and shares the Maglev legal
document section with the privacy policy. It is published with `index,follow`
and contains only user-facing, verified copy. Internal legal checks and pending
decisions are documented in
[docs/terms_and_conditions_audit.md](docs/terms_and_conditions_audit.md);
editorial instructions are in
[docs/terms_and_conditions.md](docs/terms_and_conditions.md).

### Security

The public security page lives at `/seguridad` and is administered from Maglev.
It reuses the institutional hero, navbar, footer and security sections. Verified
measures, unverified items and editorial instructions are documented in
[docs/security_page.md](docs/security_page.md) and
[docs/security_page_audit.md](docs/security_page_audit.md).

### Premium identity fingerprints

Premium identities (account email, WhatsApp number, Gmail address and redirect
email) are stored as HMAC-SHA256 fingerprints, never as raw identifiers. Set a
dedicated secret in production and keep it stable across deployments and
secret-key rotations:

```sh
export PREMIUM_IDENTITY_HMAC_SECRET="a-long-random-secret"
```

When the variable is absent, development and test derive the key from
`secret_key_base`. The migration that introduces the protection also backfills
memberships, Gmail connections, redirect emails and WhatsApp claims that already
exist. Closing an account records its current identities before deletion, so
legacy memberships do not lose their history. A returning identity keeps free
access: the dashboard shows the old membership as expired, premium features stay
locked and no new trial can be started. For manual re-runs:

```sh
bin/rails premium_identities:backfill
```

The task reports conflicts instead of aborting: a conflict means the same
identity was already claimed by another account and needs administrative review.
Accounts deleted before the backfill migration ran cannot be reconstructed if no
other record of their email remains.

### Local Speech-to-Text (faster-whisper)

Audio notes in the Expense Playground are transcribed LOCALLY with
[faster-whisper](https://github.com/SYSTRAN/faster-whisper) and FFmpeg — the
audio never leaves the machine. Setup and configuration are documented in
[docs/speech_to_text.md](docs/speech_to_text.md); quick verification:

```sh
ffmpeg -version
whisper-env/bin/python -c "from faster_whisper import WhisperModel; print('faster-whisper OK')"
```

### MCP server (AI agents)

External MCP clients can query and operate the user's finances through
`POST /mcp`. Each user connects with a revocable personal token created in
Settings → AI agents. Authentication, the tool catalogue, structured examples
and known limitations are documented in [docs/mcp.md](docs/mcp.md).

### Payment provider credentials encryption

Payment provider credentials and settings are encrypted at rest with
ActiveRecord Encryption. Production must provide all three keys:

```sh
export ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="..."
export ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="..."
export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT="..."
```

The keys can also be stored under `active_record_encryption` in encrypted
credentials. Development and test derive deterministic keys from the local
secret key base, so no additional configuration is required there. Changing
these keys makes previously encrypted provider credentials unreadable.
