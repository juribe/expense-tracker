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
