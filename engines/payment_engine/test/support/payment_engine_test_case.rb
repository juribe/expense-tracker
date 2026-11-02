class PaymentEngineTestCase < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  setup do
    PaymentEngine::Events.reset!
  end

  def create_owner(name: "Test Owner", email: nil)
    User.create!(name: name, email: email || "owner-#{SecureRandom.hex(6)}@example.com")
  end

  def create_membership_type(slug: nil, name: nil, active: true, **attributes)
    slug ||= "type-#{SecureRandom.hex(4)}"
    PaymentEngine::MembershipType.create!(
      name: name || slug.tr("-", " ").titleize,
      slug: slug,
      active: active,
      **attributes
    )
  end

  def create_payment_option(membership_type: nil, slug: nil, price: 19_900, currency: "COP",
                            billing_type: "one_time", interval: "month", interval_count: 1,
                            trial_days: 0, active: true, **attributes)
    membership_type ||= create_membership_type
    slug ||= "option-#{SecureRandom.hex(4)}"
    PaymentEngine::PaymentOption.create!(
      membership_type: membership_type,
      name: attributes.delete(:name) || slug.tr("-", " ").titleize,
      slug: slug,
      price: price,
      currency: currency,
      billing_type: billing_type,
      interval: interval,
      interval_count: interval_count,
      trial_days: trial_days,
      active: active,
      **attributes
    )
  end

  def create_membership(owner:, membership_type: nil, payment_option: nil, status: "active",
                        starts_at: 1.day.ago, expires_at: 1.month.from_now, **attributes)
    membership_type ||= payment_option&.membership_type || create_membership_type
    PaymentEngine::Membership.create!(
      owner: owner,
      membership_type: membership_type,
      payment_option: payment_option,
      status: status,
      starts_at: starts_at,
      expires_at: expires_at,
      **attributes
    )
  end

  def create_purchase(owner:, payment_option: nil, status: "pending", membership: nil, **attributes)
    payment_option ||= create_payment_option
    PaymentEngine::Purchase.create!(
      owner: owner,
      payment_option: payment_option,
      membership: membership,
      status: status,
      provider: attributes.delete(:provider) || "fake",
      **attributes
    )
  end

  def create_payment(purchase:, status: "pending", provider: "fake", amount: nil, currency: nil,
                     provider_transaction_id: nil, membership: nil, **attributes)
    purchase.payments.create!(
      provider: provider,
      amount: amount || purchase.amount,
      currency: currency || purchase.currency,
      status: status,
      provider_transaction_id: provider_transaction_id,
      membership: membership,
      **attributes
    )
  end

  def create_subscription(membership:, payment_option: nil, status: "active", provider: "fake",
                          provider_subscription_id: nil, period_start: 1.month.ago,
                          period_end: 1.month.from_now, **attributes)
    payment_option ||= membership.payment_option || create_payment_option(membership_type: membership.membership_type)
    PaymentEngine::Subscription.create!(
      membership: membership,
      payment_option: payment_option,
      provider: provider,
      provider_subscription_id: provider_subscription_id || "sub-#{SecureRandom.hex(6)}",
      status: status,
      current_period_starts_at: period_start,
      current_period_ends_at: period_end,
      next_billing_at: period_end,
      **attributes
    )
  end

  def create_webhook_event(provider: "fake", event_id: nil, event_type: "payment.approved",
                           payload: {}, status: "received")
    PaymentEngine::WebhookEvent.create!(
      provider: provider,
      event_id: event_id || "evt-#{SecureRandom.hex(6)}",
      event_type: event_type,
      payload: payload,
      status: status,
      received_at: Time.current
    )
  end

  def assert_success(result)
    assert result.success?, "Expected success but got: #{result.errors.inspect}"
    result
  end

  def assert_failure(result, code: nil)
    assert result.error?, "Expected failure but got success: #{result.data.inspect}"
    assert_equal code, result.code if code
    result
  end
end
