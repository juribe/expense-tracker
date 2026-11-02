# Changelog

## 0.1.0

Initial release.

- Membership types, payment options, memberships, purchases, payments, subscriptions,
  provider customers and webhook events.
- Polymorphic owner support with no host model dependency.
- Membership query API with deterministic `current` selection and date-aware access.
- Purchase flow with commercial snapshots and provider checkout initialization.
- Idempotent payment confirmation, rejection and refunds.
- Recurring subscriptions with renewal recording, cancellation policies and grace periods.
- Provider adapter contract, capabilities, registry and configuration.
- Webhook endpoint with signature validation, redaction, idempotency and retryable processing.
- Expiration job, Rake tasks and internal event callbacks.
- ePayco adapter (client, signature verification and event translation).
- Minitest suite covering models, services, webhooks, jobs, events, providers and concurrency.
- Installation, integration, provider and operations documentation.
