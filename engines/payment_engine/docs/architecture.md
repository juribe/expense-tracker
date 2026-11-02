# Architecture

## Isolation

`PaymentEngine` is a mountable Rails Engine with `isolate_namespace PaymentEngine`.

- All constants are under `PaymentEngine`.
- All tables use the `payment_engine_` prefix (`PaymentEngine::ApplicationRecord` sets it).
- Migrations live in `engines/payment_engine/db/migrate`.
- Routes live under the engine and are mounted by the host.
- Providers live under `PaymentEngine::Providers` and never leak into domain models.
- The host model is reached only through `belongs_to :owner, polymorphic: true`. No `User`
  constant is referenced anywhere in the engine.

## Status values

| Model | Statuses |
|---|---|
| `Membership` | `pending`, `trialing`, `active`, `expired`, `canceled` |
| `Purchase` | `pending`, `processing`, `completed`, `failed`, `canceled`, `refunded` |
| `Payment` | `pending`, `processing`, `approved`, `rejected`, `canceled`, `refunded`, `partially_refunded` |
| `Subscription` | `trialing`, `active`, `past_due`, `paused`, `canceled`, `expired` |
| `WebhookEvent` | `received`, `processing`, `processed`, `failed`, `ignored` |

Statuses are validated in Ruby and protected by database check constraints.

## Core invariants

1. **Access comes from dates, not only from status.** `Membership#active?` requires an access
   status (`active` or `trialing`), `starts_at <= now`, and `expires_at` nil or in the future.
2. **Only confirmed payments grant access.** `Purchases::Create` never activates a membership.
   Activation/extension happens in `Payments::Confirm`, `Subscriptions::RecordRenewal` or an
   explicit `Memberships::Grant` / `Memberships::StartTrial`.
3. **One open membership per owner + type.** A partial unique index on
   `(owner_type, owner_id, membership_type_id)` where status is `active`/`trialing` prevents
   duplicates. Reuse/extend is preferred over new rows, but different types can coexist.
4. **History is immutable.** Prices and durations are snapshotted on `Purchase` and on
   `Subscription`. Financial rows cannot be destroyed. Deleting a `MembershipType` or
   `PaymentOption` with history is blocked.
5. **Idempotency.** Provider transactions are unique per provider, webhook events are unique per
   provider + event id, and state transitions check current status under a row lock.
6. **Renewals extend from the end of the paid period**, not from the webhook reception time.
7. **No floating point money.** Amounts are `bigint` whole currency units.

## Purchase flow (one-time)

```text
Purchases::Create
  ├── validate owner, option and membership type
  ├── create Purchase (snapshot price/currency/period)
  ├── create pending Payment
  ├── provider.create_payment
  └── return checkout data (no membership yet)

provider confirmation
  └── Webhooks::Receive -> WebhookEvent -> ProcessJob
        └── Webhooks::Processor("payment.approved")
              └── Payments::Confirm
                    ├── lock Payment, verify amount and currency
                    ├── mark Payment approved
                    ├── lock Purchase, mark completed
                    ├── Memberships::Grant (create or extend)
                    ├── emit payment.approved / membership.activated
                    └── done
```

## Recurring flow

```text
Purchases::Create (recurring option)
  └── provider checkout / tokenization

Subscriptions::Create
  └── provider.create_subscription -> Subscription record

Provider renewal notification
  └── Webhooks::Processor("subscription.renewed")
        └── Subscriptions::RecordRenewal
              ├── reject duplicate provider transaction
              ├── create Purchase + approved Payment
              ├── extend Membership to the billed period end
              ├── update Subscription period and next_billing_at
              └── emit payment.approved / subscription.renewed / membership.renewed
```

## Cancellation

- **Immediate**: provider cancellation + subscription `canceled` + membership `canceled`.
  Access ends now.
- **At period end**: provider cancellation + `cancel_at_period_end = true`; the membership stays
  active until `current_period_ends_at`. `ExpireMembershipsJob` finalizes it as `canceled`.
- Canceling a renewal is not a refund. Refunds are recorded through `Payments::Refund`.
- Chargebacks should be translated by the provider adapter to a full `payment.refunded` event with
  the reason in metadata. With the default policy, a full refund/chargeback revokes access
  immediately and keeps the financial history.

## Failed recurring payments

`Subscriptions::RecordPaymentFailure` records a rejected payment, sets the subscription to
`past_due`, and applies `expiration_grace_period_days` once per billing period (tracked in membership
metadata). Access is not removed immediately; the expiration job handles the final state.

## Concurrency and locking

- `Payments::Confirm` locks the payment row, then the purchase, then the membership. Two
  simultaneous confirmations produce one approval and one extension.
- `Subscriptions::RecordRenewal` locks the subscription and membership and relies on the unique
  provider transaction index.
- `Memberships::Grant` locks the open membership and retries once on a unique-index conflict.
- `Purchases::Create` uses a PostgreSQL transaction advisory lock per owner + option, plus the
  duplicate window, so concurrent clicks do not create two pending purchases. On non-PostgreSQL
  adapters the window check still applies.

## Events and transactions

Services publish events with `Events.publish_after_commit`, which uses
`ActiveRecord.after_all_transactions_commit`. Host callbacks only observe committed state and are
rescued/logged; they can never roll back a payment. Events are emitted once per actual state
transition.

## Time policy

- Store UTC.
- `Duration` uses `ActiveSupport::Time#advance` for months and years.
- End-of-month behavior is clamping: Jan 31 + 1 month = Feb 28/29. The following period starts
  from the clamped date. This is deterministic and documented.
- A month is never treated as 30 days.
