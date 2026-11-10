# Public API

All services return `PaymentEngine::Result`:

```ruby
result.success?   # Boolean
result.error?     # Boolean
result.data       # payload
result.errors     # Array<String>
result.code       # Symbol
result.error_message
```

## MembershipType

```ruby
type = PaymentEngine::MembershipType.create!(
  name: "Premium",
  slug: "premium",
  description: "Full access",
  active: true,
  metadata: { "color" => "gold" }
)
```

- `slug` is unique and lowercase (`premium`, `premium-plus`).
- Deactivating a type does not revoke memberships.
- Destroying a type with options or memberships is blocked.

## PaymentOption

```ruby
option = PaymentEngine::PaymentOption.create!(
  membership_type: type,
  name: "Premium monthly",
  slug: "premium-monthly",
  price: 19_900,
  currency: "COP",
  billing_type: "one_time",     # or "recurring"
  interval: "month",            # day | month | year
  interval_count: 1,
  trial_days: 0,
  active: true,
  sort_order: 0
)

option.one_time?
option.recurring?
option.active?
option.duration                  # => PaymentEngine::Duration
option.duration.to_h             # => { "interval" => "month", "count" => 1 }
option.duration.apply_to(time)
```

Queries:

```ruby
PaymentEngine::PaymentOption.active
PaymentEngine::PaymentOption.for("premium")              # only active options
PaymentEngine::PaymentOption.find_by_slug("premium-monthly")
PaymentEngine::PaymentOption.find_by_slug("premium-monthly", active_only: false)
```

## Membership queries

```ruby
PaymentEngine::Membership.active?(owner)
PaymentEngine::Membership.active?(owner, type: "premium")
PaymentEngine::Membership.current(owner)
PaymentEngine::Membership.current(owner, type: "premium")
PaymentEngine::Membership.current_type(owner)
PaymentEngine::Membership.all_active(owner)
PaymentEngine::Membership.expires_at(owner)
PaymentEngine::Membership.days_remaining(owner)
PaymentEngine::Membership.expiring_soon?(owner, days: 7)
PaymentEngine::Membership.has_type?(owner, slug: "premium")
PaymentEngine::Membership.has_type?(owner, slug: "premium", active_only: false)
```

Deterministic priority for `current`:

1. `active` before `trialing`.
2. Indefinite memberships (`expires_at` nil) before dated ones.
3. Later `expires_at`.
4. Later `starts_at`.
5. Higher id.

Instance methods:

```ruby
membership.active?
membership.pending?
membership.trialing?
membership.expired?
membership.canceled?
membership.expiring_soon?(days: 7)
membership.days_remaining
membership.expires_in
membership.remaining_time
membership.membership_type
membership.payment_option
membership.subscription
```

## Purchases

```ruby
result = PaymentEngine::Purchases::Create.call(
  owner: owner,
  payment_option: option,
  provider: :epayco,     # optional; falls back to config.default_provider
  description: nil,
  metadata: {}
)

result.data[:purchase]   # pending Purchase with snapshot
result.data[:payment]    # pending Payment
result.data[:checkout]   # adapter-specific checkout data
```

Failure codes include `:invalid_owner`, `:invalid_option`, `:inactive_option`,
`:inactive_membership_type`, `:unsupported_operation`, `:duplicate_purchase`,
`:provider_not_configured`, `:provider_error`.

## Payments

```ruby
PaymentEngine::Payments::Confirm.call(
  payment: payment,
  provider_transaction_id: "txn-123",
  amount: 19_900,
  currency: "COP",
  paid_at: Time.current,
  payment_method: "card",
  metadata: {}
)

PaymentEngine::Payments::Reject.call(
  payment: payment,
  failure_reason: "insufficient funds"
)

PaymentEngine::Payments::Refund.call(
  payment: payment,
  amount: nil,          # nil or full amount => full refund
  reason: "customer request"
)
```

`Confirm` is idempotent per payment and rejects amount/currency mismatches. A second approved
payment for a completed purchase is recorded but never extends access again.

## Subscriptions

```ruby
PaymentEngine::Subscriptions::Create.call(
  membership: membership,
  payment_option: option,
  provider: :epayco,
  provider_subscription_id: nil,
  status: "active",
  starts_at: nil,
  ends_at: nil,
  next_billing_at: nil,
  trial_ends_at: nil
)

PaymentEngine::Subscriptions::Current.call(owner: owner)
PaymentEngine::Subscriptions::Renew.call(subscription)
PaymentEngine::Subscriptions::Cancel.call(subscription, immediately: false)

PaymentEngine::Subscriptions::RecordRenewal.call(
  subscription: subscription,
  provider_transaction_id: "txn-renewal",
  amount: 19_900,
  currency: "COP",
  paid_at: nil,
  period_starts_at: nil,
  period_ends_at: nil
)

PaymentEngine::Subscriptions::RecordPaymentFailure.call(
  subscription: subscription,
  failure_reason: "insufficient funds",
  provider_transaction_id: "txn-failed"
)
```

## Membership administration

```ruby
PaymentEngine::Memberships::Grant.call(
  owner: owner,
  membership_type: type,
  payment_option: option,
  duration: PaymentEngine::Duration.new(interval: "month", count: 1),
  membership: nil,
  starts_at: nil,
  status: "active",
  metadata: {}
)

# Indefinite free/manual membership (no duration, no expiration):
PaymentEngine::Memberships::Grant.call(
  owner: owner,
  membership_type: free_type,
  expires_at: nil,
  metadata: { "source" => "admin" }
)

PaymentEngine::Memberships::StartTrial.call(owner: owner, payment_option: option)
PaymentEngine::Memberships::Expire.call(membership)
```

`Grant` creates the membership when no open access exists; otherwise it extends the existing one
from the later of its expiration and now. Pass `expires_at:` for a fixed or indefinite manual
grant; pass `duration:` for a calculated period.

Subscriptions snapshot their commercial conditions (`price`, `currency`, `billing_type`,
`duration`) when they are created. Later `PaymentOption` changes affect only new subscriptions and
new purchases; existing renewals keep their original price and period.

## Webhooks

```ruby
PaymentEngine::Webhooks::Receive.call(
  provider_name: "epayco",
  payload: request.request_parameters,
  headers: request.headers.to_h,
  raw_body: request.raw_post
)

PaymentEngine::Webhooks::Processor.call(event)
```

## Configuration

```ruby
PaymentEngine.configure do |config|
  config.default_provider             = :epayco
  config.providers                    = { epayco: { ... } }
  config.membership_timezone          = "UTC"
  config.expiration_grace_period_days = 0
  config.revoke_access_on_refund      = true
  config.purchase_duplicate_window_minutes = 15
  config.webhook_tolerance_seconds    = 300
  config.logger                       = Rails.logger
end
```

## Events

```ruby
PaymentEngine.on(:membership_activated) { |event| ... }
PaymentEngine.on(:payment_approved) { |event| ... }
```

Event names use underscores in callbacks. `ActiveSupport::Notifications` receives
`payment_engine.membership_activated`, etc.
