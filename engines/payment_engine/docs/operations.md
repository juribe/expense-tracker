# Operations

## Daily maintenance

Recommended: run once per day from the host scheduler.

```bash
bin/rails payment_engine:expire_memberships
```

Equivalent:

```ruby
PaymentEngine::Jobs::ExpireMembershipsJob.perform_now
```

The job:

1. Finalizes subscriptions with `cancel_at_period_end` whose period ended (membership becomes
   `canceled` when its paid period is over).
2. Expires memberships whose `expires_at` passed while still `active`/`trialing`.
3. Expires subscriptions whose `current_period_ends_at` passed.

It is idempotent; repeated executions produce no additional changes or events.

## Webhooks

Endpoint: `POST /payment_engine/webhooks/:provider`.

The engine responds:

| Situation | HTTP |
|---|---|
| Valid new or duplicate event | 200 |
| Invalid signature | 401 |
| Unknown provider | 404 |
| Malformed event | 422 |

Processing runs asynchronously in `PaymentEngine::Webhooks::ProcessJob` with up to 5 retries.
Failed events remain in `payment_engine_webhook_events` with `status = failed` and an error message.

Reprocess manually:

```bash
bin/rails payment_engine:reprocess_webhook[123]
```

```ruby
event = PaymentEngine::WebhookEvent.find(123)
PaymentEngine::Webhooks::Processor.call(event)
```

## Monitoring

Useful signals:

```ruby
PaymentEngine::WebhookEvent.where(status: "failed").count
PaymentEngine::WebhookEvent.where(status: "failed").recent.limit(20)
PaymentEngine::WebhookEvent.where(status: "received").where("received_at < ?", 10.minutes.ago)
PaymentEngine::Payment.where(status: "processing").where("updated_at < ?", 1.hour.ago)
PaymentEngine::Subscription.where(status: "past_due")
```

Payloads are redacted before persistence, so they are safe to inspect for ids, amounts and
statuses. Do not add logging of raw request bodies or provider credentials.

## Data retention

- Never delete `payment_engine_payments`, `payment_engine_purchases` or
  `payment_engine_memberships`.
- `payment_engine_webhook_events` are audit records; a retention policy can archive/delete old
  processed events if the host's compliance rules allow it.
- `ProviderCustomer` stores only provider customer references. Card data never enters the engine.

## Changing prices or options

- Existing purchases keep their snapshot.
- Existing subscriptions keep their period and price until the next renewal.
- Deactivate an option (`active: false`) to stop new purchases; existing access is unaffected.
- Deactivate a membership type to stop new purchases; existing memberships remain valid.

## Time zones

Timestamps are stored in UTC. `membership_timezone` affects calendar calculations and presentation.
Changing it does not rewrite stored timestamps.

## Failure recovery

- **Provider error during purchase**: purchase becomes `failed`, payment `rejected`. The owner can
  retry with a new purchase.
- **Amount/currency mismatch**: confirmation fails, payment stays pending/rejected; investigate the
  provider transaction before retrying.
- **Duplicate webhook**: acknowledged and ignored.
- **Duplicate renewal transaction**: `Subscriptions::RecordRenewal` returns `:already_processed`
  without extending.
- **Worker crash**: the event is `processing` or `failed`; retry is safe because operations are
  idempotent.
