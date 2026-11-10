# PaymentEngine

`PaymentEngine` is a reusable Rails Engine that provides the complete infrastructure for
membership-based monetization: membership types, payment options, purchases, payments,
recurring subscriptions, payment provider adapters, webhooks, expirations and lifecycle events.

The engine is independent from any host application. It does not assume a `User` model, does not
read or write host tables, and only communicates through a polymorphic `owner` association and a
small public API.

## Requirements

- Ruby >= 3.1
- Rails >= 7.2, < 9.0 (tested with Rails 8.1)
- ActiveRecord
- ActiveJob (Sidekiq, Solid Queue or any adapter)
- PostgreSQL is the reference database (JSONB, partial unique indexes and check constraints)
- Minitest for the engine test suite

## Installation

Add the engine to the host application:

```ruby
# Gemfile
gem "payment_engine", path: "engines/payment_engine"
# or, when published:
# gem "payment_engine"
```

Then install migrations, mount the engine and create an initializer:

```bash
bundle install
bin/rails payment_engine:install:migrations
bin/rails db:migrate
```

```ruby
# config/routes.rb
mount PaymentEngine::Engine => "/payment_engine"
```

```ruby
# config/initializers/payment_engine.rb
PaymentEngine.configure do |config|
  config.default_provider = :epayco

  config.providers = {
    epayco: {
      public_key: ENV["EPAYCO_PUBLIC_KEY"],
      private_key: ENV["EPAYCO_PRIVATE_KEY"],
      customer_id: ENV["EPAYCO_CUSTOMER_ID"],
      p_key: ENV["EPAYCO_P_KEY"],
      confirmation_url: "https://example.com/payment_engine/webhooks/epayco"
    }
  }

  config.membership_timezone = "UTC"
  config.expiration_grace_period_days = 0
end
```

The generator `bin/rails generate payment_engine:install` writes the initializer, mounts the
engine and installs migrations for you.

The host only needs a model that can act as `owner`:

```ruby
class User < ApplicationRecord
  has_many :memberships, as: :owner, class_name: "PaymentEngine::Membership"
  has_many :purchases,   as: :owner, class_name: "PaymentEngine::Purchase"
end
```

No columns are added to the host model.

## Domain model

```text
MembershipType
  └── PaymentOptions
        └── Purchases
              └── Payments

MembershipType
  └── Memberships
        ├── Purchases
        ├── Payments
        └── Subscriptions

Owner (polymorphic)
  ├── Memberships
  ├── Purchases
  └── ProviderCustomers
```

| Model | Responsibility |
|---|---|
| `MembershipType` | Access level offered by the application (Free, Premium, Pro...). |
| `PaymentOption` | Commercial way to buy a type: price, currency, billing type and period. |
| `Membership` | Current access right of an owner. Kept as history after expiring or canceling. |
| `Purchase` | Commercial intent with a price/period snapshot. Can have several payment attempts. |
| `Payment` | Financial transaction attempt. Only approved payments grant access. |
| `Subscription` | Recurring renewal agreement with a provider. Never used for one-time payments. |
| `ProviderCustomer` | Owner-to-provider customer reference. Never stores card data. |
| `WebhookEvent` | Auditable, redacted provider event with idempotent processing state. |

## Public API

### Membership access

```ruby
PaymentEngine::Membership.active?(owner)                # any active membership
PaymentEngine::Membership.active?(owner, type: "premium")
PaymentEngine::Membership.current(owner)                # deterministic selection
PaymentEngine::Membership.current(owner, type: "premium")
PaymentEngine::Membership.current_type(owner)
PaymentEngine::Membership.all_active(owner)
PaymentEngine::Membership.expires_at(owner)
PaymentEngine::Membership.days_remaining(owner)
PaymentEngine::Membership.expiring_soon?(owner, days: 7)
PaymentEngine::Membership.has_type?(owner, slug: "premium")
```

When several memberships are active, `current` uses a deterministic priority: `active` before
`trialing`, indefinite memberships first, then the latest expiration, latest start and highest id.
Use `type:` whenever the selection would otherwise be ambiguous.

Access is always evaluated from **status and dates**. A membership whose `expires_at` has passed
does not grant access even if the expiration job has not run yet.

### Membership instances

```ruby
membership.active?
membership.pending?
membership.trialing?
membership.expired?
membership.canceled?
membership.expiring_soon?(days: 7)
membership.days_remaining        # complete days, nil when there is no expiration
membership.expires_at
membership.expires_in            # seconds, nil when indefinite
membership.remaining_time        # ActiveSupport::Duration
membership.membership_type
membership.payment_option
membership.subscription
```

### Payment options

```ruby
PaymentEngine::PaymentOption.active
PaymentEngine::PaymentOption.for("premium")
PaymentEngine::PaymentOption.for("premium").ordered
PaymentEngine::PaymentOption.find_by_slug("premium-monthly")
PaymentEngine::PaymentOption.find_by_slug("premium-monthly", active_only: false)
```

### Creating a purchase

```ruby
result = PaymentEngine::Purchases::Create.call(
  owner: current_user,
  payment_option: option,
  provider: :epayco
)

if result.success?
  result.data[:purchase]   # PaymentEngine::Purchase (pending)
  result.data[:payment]    # PaymentEngine::Payment (pending)
  result.data[:checkout]   # provider data needed to redirect the buyer
else
  result.errors
end
```

`Purchases::Create` validates the option and owner, stores the commercial snapshot, creates the
purchase and its pending payment, and starts the provider flow. **It never activates a membership.**
Activation happens only after a confirmed payment or an authorized trial.

### Subscriptions

```ruby
PaymentEngine::Subscriptions::Create.call(membership: membership, payment_option: option, provider: :epayco)
PaymentEngine::Subscriptions::Current.call(owner: current_user)
PaymentEngine::Subscriptions::Renew.call(subscription)
PaymentEngine::Subscriptions::Cancel.call(subscription, immediately: false)
```

Renewals extend access only after a confirmed charge. The webhook processor uses
`Subscriptions::RecordRenewal`, which is idempotent per provider transaction.

### Result objects

Every service returns a `PaymentEngine::Result`:

```ruby
result.success?   # Boolean
result.error?     # Boolean
result.data       # payload
result.errors     # Array<String>
result.code       # Symbol with the outcome (e.g. :approved, :duplicate_purchase)
```

Commercial validation failures are results, not exceptions. Exceptions are reserved for
unexpected/infrastructure errors.

## Webhooks

```text
POST /payment_engine/webhooks/:provider
```

The controller identifies the provider adapter, validates authenticity, redacts and stores the
event, avoids duplicates with a unique `provider + event_id` index, and enqueues
`PaymentEngine::Webhooks::ProcessJob`. Financial work never runs inside the HTTP request.

- Duplicate deliveries are acknowledged without creating a second event.
- Event payloads are redacted (cards, CVV, tokens, secrets, signatures) before persistence.
- Events are marked `processed` only after the business operation succeeds.
- Failed events keep the error and can be retried or reprocessed with
  `PaymentEngine::Webhooks::Processor.call(event)` or the Rake task.

Normalized internal event types:

```text
payment.approved
payment.rejected
payment.refunded
subscription.created
subscription.renewed
subscription.canceled
subscription.payment_failed
```

Each adapter translates its provider's real events into these types. Unknown events are stored
as `ignored` instead of failing.

## Expiration and maintenance

```ruby
PaymentEngine::Jobs::ExpireMembershipsJob.perform_now
```

```bash
bin/rails payment_engine:expire_memberships
bin/rails payment_engine:reprocess_webhook[EVENT_ID]
```

The job expires memberships whose period ended, finalizes cancellations scheduled at period end,
and expires subscriptions whose period ended. It is idempotent.

The engine does not depend on Sidekiq Cron, Solid Queue recurring tasks or any specific scheduler.
Schedule the Rake task or the job with the host's usual mechanism (daily is recommended). Do not
rely only on the job for access control: date checks always apply in real time.

## Events

```ruby
PaymentEngine.on(:membership_activated) do |event|
  event[:membership] # => PaymentEngine::Membership
end
```

Available events:

```text
membership.activated / membership.expired / membership.renewed / membership.canceled
subscription.created / subscription.renewed / subscription.payment_failed / subscription.canceled
payment.approved / payment.rejected / payment.refunded
```

Callbacks run after the surrounding transaction commits. A failing host callback is logged and
never rolls back a confirmed payment. The same events are instrumented through
`ActiveSupport::Notifications` as `payment_engine.<event_name>`.

## Payment providers

```ruby
PaymentEngine.register_provider(:epayco, PaymentEngine::Providers::Epayco)
PaymentEngine.provider(:epayco)

provider.supports?(:recurring_payments)
provider.supports?(:refunds)
provider.supports?(:tokenization)
provider.supports?(:subscription_cancellation)
```

Unsupported operations return a controlled `:unsupported_operation` result. The engine never
simulates a capability the provider does not have. All provider-specific code lives under
`PaymentEngine::Providers`; domain models never reference ePayco or any other gateway.

See [`docs/providers.md`](docs/providers.md) to implement a new adapter.

### ePayco

The ePayco adapter implements the documented confirmation signature:

```text
SHA256(p_cust_id_cliente^p_key^x_ref_payco^x_transaction_id^x_amount^x_currency_code)
```

It also maps approved/rejected/refunded states to internal events, and exposes customer, payment
session, refund and subscription operations through a configurable APIFY client. ePayco's API
evolves; before going live, verify endpoint paths and payloads against the current ePayco
documentation and the merchant account's enabled products. Recurring charges require a payment
method that supports tokenization and a subscription plan enabled in the merchant account.

## Money, dates and time zones

- Amounts are stored as `bigint` in whole currency units, as required by the specification
  (`$19.900 COP` is stored as `19900`). No `Float` is used for money.
- Every timestamp is stored in UTC. `membership_timezone` only controls presentation and calendar
  calculations.
- Periods use ActiveSupport calendar arithmetic. A "month" is not 30 days and an "year" is a
  calendar year.
- End-of-month policy: the day is clamped deterministically. January 31 + 1 month = February 28
  (or February 29 in a leap year); the following period starts from the clamped date.

## Testing the engine

```bash
cd engines/payment_engine
bundle install
RAILS_ENV=test bundle exec rake app:db:create app:db:migrate
bundle exec rails test
```

The suite covers models, services, webhooks, jobs, events, provider adapters and concurrency
(duplicate confirmations and duplicate purchases).

## Design decisions and limitations

- **No administrative UI is included.** Administration is available through the public models and
  services. A host can build its own UI and authorize it with its own authentication system.
- **No scheduler dependency.** The host schedules the job or Rake task.
- **No card data storage.** Only provider customer ids and references are stored.
- **Full refunds revoke access by default** (`config.revoke_access_on_refund = true`). Partial
  refunds keep access. Change the setting if the business policy differs.
- **Provider retries and webhook re-delivery** are safe because payment confirmation, renewal and
  purchase creation are idempotent and guarded by unique indexes and row locks.
- **Owner deletion**: memberships are financial history and cannot be destroyed. Hosts should use
  soft deletion for owners instead of hard deletes.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — invariants, flows, idempotency and locking.
- [`docs/public_api.md`](docs/public_api.md) — complete API reference and examples.
- [`docs/providers.md`](docs/providers.md) — adapter contract, capability matrix and ePayco.
- [`docs/integration.md`](docs/integration.md) — host application integration (including Yogasto).
- [`docs/operations.md`](docs/operations.md) — scheduling, monitoring and reprocessing.

## License

MIT.
