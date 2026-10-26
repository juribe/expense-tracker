# Mail inbound

Provider-neutral inbound email flow for the Expense Tracker.

## Architecture

```text
POST /webhooks/email
        │
        ▼
MailInboundService#accept
  ├─ valida firma del provider
  ├─ persiste MailInboundDelivery
  └─ encola MailInboundHandleJob
        │
        ▼  HTTP 202
MailInboundHandleJob
  ├─ MailInboundService#handle_email
  ├─ Cloudflare: parsea MIME
  ├─ Resend: consulta Receiving API
  ├─ crea/actualiza ProcessedEmail
  └─ encola MailInboundProcessJob
        │
        ▼
MailInboundProcessJob
  └─ MailInbound::Processor → Gmail::ExpenseImporter
```

The HTTP request only validates the provider signature and persists a durable
delivery. MIME parsing, Resend API calls and AI work happen in jobs.

## Providers

`MAIL_INBOUND_PROVIDER` selects the active provider:

```sh
MAIL_INBOUND_PROVIDER=cloudflare
# or
MAIL_INBOUND_PROVIDER=resend
```

The HTTP route is always `POST /webhooks/email`.

### Cloudflare

- Signature: HMAC over timestamp, recipient and SHA-256 of the raw MIME.
- `build_delivery` stores the raw MIME and a stable body hash as `external_id`.
- `handle_email` parses MIME with `MailInbound::MessageParser`.

### Resend

- Signature: Svix using `RESEND_WEBHOOK_SECRET`.
- `build_delivery` stores the `email.received` event and `email_id`.
- `handle_email` fetches text, HTML, headers and attachment metadata from
  `GET /emails/receiving/{email_id}` using `RESEND_API_KEY`.

## Delivery persistence

`mail_inbound_deliveries` stores the raw provider data before the handle job:

- `provider`, `external_id` (unique per provider)
- `status`: `received`, `handling`, `handled`, `failed`
- `raw_body`, `headers`, `params`
- `user`, optional `processed_email`
- `attempts`, `last_error`, `processed_at`

This keeps Solid Queue arguments small and allows retrying without asking the
provider to resend the webhook.

## Jobs

### `MailInboundHandleJob`

- Claims the delivery (`received`/`failed`/stale `handling` → `handling`).
- Calls `MailInboundService#handle_email`.
- Creates or updates `ProcessedEmail` through `MailInbound::Acceptance`.
- Enqueues `MailInboundProcessJob`.
- Retries transient/API errors up to 5 times.
- Marks permanent payload/configuration errors as `failed`.

### `MailInboundProcessJob`

Runs the existing detector, AI extractor, source recognition,
`Gmail::TransactionRecorder` and `Expenses::Create`. It is idempotent through
`ProcessedEmail` and the transaction deduplication index.

`InboundEmailProcessJob` remains as a compatibility subclass for jobs queued
before the refactor.

## HTTP responses

| Case | HTTP |
| --- | --- |
| New delivery + handle job enqueued | 202 |
| Duplicate delivery | 200 |
| Invalid signature | 401 |
| Unknown recipient | 403 |
| Tenant mismatch | 409 |
| Payload too large | 413 |
| Unsupported content type | 415 |
| Invalid payload | 422 |
| Missing configuration | 500 |
| Queue unavailable | 503 |

## Configuration

### Common

```sh
MAIL_INBOUND_PROVIDER=cloudflare
INBOUND_EMAIL_RECIPIENT=receive@samyreplies.com
INBOUND_EMAIL_USER_EMAIL=jse.uribe@gmail.com
INBOUND_EMAIL_USER_MAP=user1=jse.uribe@gmail.com
```

`receive+user1@samyreplies.com` maps to the configured user. Tokens not present
in the map are rejected when the map is configured. Without a map, every token
uses `INBOUND_EMAIL_USER_EMAIL`.

### Cloudflare

```sh
INBOUND_EMAIL_SECRET=...
INBOUND_EMAIL_SECRET_PREVIOUS=...   # optional rotation
INBOUND_EMAIL_MAX_BYTES=10485760
INBOUND_EMAIL_MAX_SKEW_SECONDS=300
```

Worker config lives in `cloudflare/email-router/wrangler.toml`:

- `RAILS_INBOUND_EMAIL_URL=https://whatsapp.samyreplies.com/webhooks/email`
- `ALLOWED_RECIPIENTS=receive@samyreplies.com,receive+*@samyreplies.com`
- `MAX_EMAIL_BYTES=10485760`
- `REQUEST_TIMEOUT_MS=15000`

Secret:

```sh
cd cloudflare/email-router
npx wrangler secret put INBOUND_EMAIL_SECRET
```

### Resend

```sh
RESEND_WEBHOOK_SECRET=...
RESEND_API_KEY=...
```

Resend webhooks must be configured for `email.received`.

## Cloudflare setup already applied

- Root MX moved from the previous inbound provider to Cloudflare Email Routing.
- `support_subaddress=true` and `status=ready`.
- Rule `Expense Tracker inbound` routes `receive@samyreplies.com` to
  `expense-tracker-inbound-email`.
- Worker variables and `INBOUND_EMAIL_SECRET` are configured.

The Cloudflare Worker remains Cloudflare-specific; Rails no longer depends on it.

## Observability and recovery

```bash
bin/rails runner 'pp MailInboundDelivery.order(created_at: :desc).limit(10).pluck(:id, :provider, :external_id, :status, :last_error)'
bin/rails runner 'MailInboundHandleJob.perform_now("DELIVERY_ID")'
bin/rails runner 'MailInboundProcessJob.perform_now("PROCESSED_EMAIL_ID")'
```

Logs use `[MailInbound]`, `[MailInboundHandleJob]` and
`[MailInboundProcessJob]`. Message bodies, secrets and financial amounts are not
logged.

## Security

- HTTPS only in production.
- Provider secrets are read from environment variables and never logged.
- Signatures are validated before content is stored or fetched.
- Cloudflare HMAC comparison is constant-time.
- Cloudflare timestamp tolerance defaults to 300 seconds.
- Request bodies and attachment bytes are not logged.
- CSRF is skipped only for `Webhooks::EmailController#create`.

## Gmail

Gmail/OAuth is a separate polling integration and is not a `MailInbound`
provider. The Gmail import pipeline is reused only at the final
`Gmail::ExpenseImporter` stage.

## Limits

- Cloudflare inbound limit: 25 MiB; integration default: 10 MiB.
- Resend content retrieval depends on the Receiving API and `RESEND_API_KEY`.
- Attachments are stored as metadata only; bytes are not processed.
- Raw MIME/event data is stored in `mail_inbound_deliveries.raw_body` until the
  handle job completes. Apply retention/cleanup if needed.
- Cloudflare Workers Free has 10 ms CPU and 128 MB memory per invocation.
