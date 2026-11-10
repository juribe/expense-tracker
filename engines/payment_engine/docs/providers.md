# Payment providers

Provider-specific code lives only under `PaymentEngine::Providers`. Domain models and services
never reference a gateway.

## Contract

Adapters inherit from `PaymentEngine::Providers::Base` and declare capabilities:

```ruby
class MyProvider < PaymentEngine::Providers::Base
  def self.capabilities
    %i[customers payments refunds webhooks]
  end
end
```

Available operations (all return `PaymentEngine::Result`):

```ruby
provider.create_customer(owner:, email: nil, metadata: {})
provider.create_payment(purchase:, payment:, customer: nil, return_url: nil, confirmation_url: nil)
provider.fetch_payment(provider_transaction_id:)
provider.create_subscription(subscription:, customer: nil, payment_method_token: nil)
provider.cancel_subscription(provider_subscription_id:, immediately: false)
provider.fetch_subscription(provider_subscription_id:)
provider.refund_payment(provider_transaction_id:, amount: nil, reason: nil)
provider.verify_webhook(payload:, headers: {}, raw_body: nil)
provider.parse_webhook(payload:, headers: {}, raw_body: nil)
```

`supports?(capability)` returns false for undeclared capabilities, and the default implementation
returns a `:unsupported_operation` failure. Never fake a capability.

Capability names used by the engine:

| Capability | Used by |
|---|---|
| `:payments` | `Purchases::Create` |
| `:recurring_payments` | recurring purchases, `Subscriptions::Create`, `Renew` |
| `:subscription_cancellation` | `Subscriptions::Cancel` |
| `:refunds` | refund flows |
| `:tokenization` | tokenized/recurring card flows |
| `:customers` | `ProviderCustomer` flows |
| `:webhooks` | webhook adapters |

## Registry

```ruby
PaymentEngine.register_provider(:my_provider, MyProvider)
PaymentEngine.provider(:my_provider)
PaymentEngine.provider?(:my_provider)
PaymentEngine.configuration.providers[:my_provider] # credentials
```

Provider instances are cached and rebuilt after `PaymentEngine.configure` or
`register_provider`. Domain models never change when the host switches providers.

## Normalized webhook data

`parse_webhook` must return:

```ruby
PaymentEngine::Result.success(
  data: {
    event_id: "unique-event-id",
    event_type: "payment.approved", # see list below
    provider_transaction_id: "txn-123",
    purchase_id: 42,
    subscription_id: nil,
    provider_subscription_id: nil,
    amount: 19900,
    currency: "COP",
    paid_at: Time.current,
    payment_method: "card",
    failure_reason: nil,
    period_starts_at: nil,
    period_ends_at: nil,
    next_billing_at: nil,
    status: nil,
    metadata: {}
  }
)
```

Internal event types:

```text
payment.approved
payment.rejected
payment.refunded
subscription.created
subscription.renewed
subscription.canceled
subscription.payment_failed
```

`verify_webhook` must validate the provider's signature/authentication before anything is stored.
Use constant-time comparison (`ActiveSupport::SecurityUtils.secure_compare`).

## Implementing a new adapter

1. Create `PaymentEngine::Providers::MyProvider < Base`.
2. Declare only the capabilities the provider really supports.
3. Implement the operations used by those capabilities.
4. Map real webhook events to the normalized event types.
5. Validate signatures using the raw body/headers when required.
6. Keep secrets in configuration or environment variables. Never log payload secrets.
7. Add adapter tests with a stubbed HTTP client; do not hit the network in the test suite.
8. Document provider-specific limitations (for example, only card payments support recurrence).

## ePayco adapter

`PaymentEngine::Providers::Epayco` includes:

- `Epayco::Client` — APIFY REST client with `POST /login`, customer, token, payment session,
  transaction detail, refund and recurring plan/subscription endpoints. Endpoints are configurable
  through `base_url` if ePayco changes them.
- `Epayco::WebhookHandler` — signature verification and state translation.

Configuration:

```ruby
config.providers = {
  epayco: {
    public_key: ENV["EPAYCO_PUBLIC_KEY"],
    private_key: ENV["EPAYCO_PRIVATE_KEY"],
    customer_id: ENV["EPAYCO_CUSTOMER_ID"],
    p_key: ENV["EPAYCO_P_KEY"],
    plan_id: ENV["EPAYCO_PLAN_ID"],          # required for subscriptions
    confirmation_url: "https://example.com/payment_engine/webhooks/epayco"
  }
}
```

Signature (documented by ePayco):

```text
SHA256(p_cust_id_cliente^p_key^x_ref_payco^x_transaction_id^x_amount^x_currency_code)
```

The handler maps `x_cod_response` / `x_response` to:

| ePayco state | Internal event |
|---|---|
| 1 / Aceptada | `payment.approved` |
| 2, 4, 9, 10, 11 / Rechazada, Fallida, Expirada, Abandonada | `payment.rejected` |
| 3 / Pendiente | `payment.pending` (stored and ignored by the processor) |
| 6 / Reversada | `payment.refunded` |

`x_id_factura` must contain the `Purchase` id; the adapter uses it to locate the pending payment.
Recurring confirmations are processed as payment approvals against the renewal purchase and extend
the membership through `Payments::Confirm`.

Before production, verify the current ePayco documentation for APIFY request/response shapes and
confirm that the merchant account has subscriptions and tokenization enabled. The adapter never
assumes that every payment method supports recurrence.
