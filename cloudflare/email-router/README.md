# Cloudflare Email Worker — Expense Tracker

Receives mail through Cloudflare Email Routing and forwards the original MIME
body to Rails at `POST /webhooks/email`.

## How it works

1. Email Routing matches the configured recipient and invokes this Worker's
   `email()` handler.
2. The Worker rejects unexpected recipients and messages over the size limit.
3. It computes `SHA-256(raw MIME)` and signs
   `<timestamp>\n<recipient>\n<body hash>` with HMAC-SHA256.
4. It POSTs the raw MIME to Rails with the timestamp, recipient and signature.
5. Rails accepts only `2xx` responses. Permanent `4xx` responses become
   `setReject`; temporary failures are thrown so Cloudflare can retry.

The Worker never logs message bodies, subjects, amounts or the shared secret.

## Requirements

- Node.js 20+
- A Cloudflare zone using Cloudflare DNS with Email Routing available
- Cloudflare Wrangler 4.113.0+ if you want to manage the routing rule with
  `addresses`

## Configure

```sh
cd cloudflare/email-router
npm install
```

Edit `wrangler.toml`:

- `RAILS_INBOUND_EMAIL_URL`: public HTTPS Rails endpoint
- `ALLOWED_RECIPIENTS`: comma-separated recipients or wildcard patterns
  (for example, `receive@samyreplies.com,receive+*@samyreplies.com`)
- `MAX_EMAIL_BYTES`: default 10 MiB; Cloudflare's inbound ceiling is 25 MiB
- `REQUEST_TIMEOUT_MS`: Rails request timeout

Store the shared secret (same value as Rails `INBOUND_EMAIL_SECRET`):

```sh
npx wrangler secret put INBOUND_EMAIL_SECRET
```

Do not put the secret in `wrangler.toml`, source control or logs.

## Local test

Run the Worker unit tests (no Cloudflare account or network needed):

```sh
npm test
```

Rails environment:

```sh
INBOUND_EMAIL_SECRET=dev_inbound_secret
INBOUND_EMAIL_RECIPIENT=receive@samyreplies.com
INBOUND_EMAIL_USER_EMAIL=your-user@example.com
INBOUND_EMAIL_USER_MAP=user1=your-user@example.com
```

Start Rails and a Solid Queue worker:

```sh
bin/rails server
bin/rails solid_queue:start
```

Create `cloudflare/email-router/.dev.vars` (ignored by Git):

```text
INBOUND_EMAIL_SECRET=dev_inbound_secret
RAILS_INBOUND_EMAIL_URL=http://localhost:3000/webhooks/email
```

Run the Worker locally and send the fixture through Wrangler's local email
endpoint:

```sh
npx wrangler dev
```

In another terminal:

```sh
curl --request POST 'http://localhost:8787/cdn-cgi/local/email' \
  --url-query 'from=notificaciones@bank.example' \
  --url-query 'to=receive+user1@samyreplies.com' \
  --data-binary @fixtures/bank-alert.eml
```

The Rails log should show `[MailInboundHandleJob] ... status=handled`; the job
then enqueues the existing expense pipeline.

## Deploy

```sh
npx wrangler deploy --dry-run
npx wrangler deploy
```

Then create the Email Routing rule in the Cloudflare dashboard:

- Domain: `samyreplies.com`
- Email pattern: `receive` (with subaddressing enabled, so
  `receive+anything@samyreplies.com` matches)
- Action: **Send to a Worker**
- Worker: `expense-tracker-inbound-email`

Alternatively, after verifying that no existing rule uses the address, uncomment
`addresses = ["receive@samyreplies.com"]` in `wrangler.toml` and deploy.
Wrangler will create/manage that rule.

Do not change existing MX records or other routing rules. Email Routing onboarding
may add MX/SPF/DKIM records; review them before applying.

## Inspect failures

```sh
npx wrangler tail
```

Cloudflare dashboard → **Compute → Email Service → Email Routing → Activity**.
Rails side:

```sh
bin/rails runner 'pp MailInboundDelivery.order(created_at: :desc).limit(5).pluck(:id, :provider, :external_id, :status, :last_error)'
bin/rails runner 'MailInboundProcessJob.perform_now("PROCESSED_EMAIL_ID")'
```
