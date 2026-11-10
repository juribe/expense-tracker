require "test_helper"

class SubscriptionsLifecycleTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @type = create_membership_type(slug: "premium")
    @option = create_payment_option(membership_type: @type, slug: "premium-auto",
                                    billing_type: "recurring", price: 19_900)
    @membership = create_membership(owner: @owner, membership_type: @type, payment_option: @option,
                                    starts_at: 1.month.ago, expires_at: 1.month.from_now)
  end

  test "creates a subscription through the provider" do
    result = PaymentEngine::Subscriptions::Create.call(
      membership: @membership,
      payment_option: @option,
      provider: :fake
    )

    subscription = assert_success(result).data
    assert_equal "fake", subscription.provider
    assert subscription.provider_subscription_id.present?
    assert_equal @membership.starts_at, subscription.current_period_starts_at
    assert_equal @option.duration.apply_to(@membership.starts_at), subscription.current_period_ends_at
  end

  test "returns an existing subscription for the same provider id" do
    first = PaymentEngine::Subscriptions::Create.call(
      membership: @membership, payment_option: @option, provider_subscription_id: "external-1"
    )
    second = PaymentEngine::Subscriptions::Create.call(
      membership: @membership, payment_option: @option, provider_subscription_id: "external-1"
    )

    assert_success(first)
    assert_success(second)
    assert_equal :already_exists, second.code
    assert_equal first.data.id, second.data.id
  end

  test "rejects recurring subscriptions for providers without that capability" do
    assert_failure(
      PaymentEngine::Subscriptions::Create.call(
        membership: @membership, payment_option: @option, provider: :limited
      ),
      code: :unsupported_operation
    )
  end

  test "immediate cancellation revokes access" do
    subscription = create_subscription(membership: @membership, payment_option: @option)

    result = PaymentEngine::Subscriptions::Cancel.call(subscription, immediately: true)

    assert_success(result)
    assert_equal "canceled", subscription.reload.status
    assert_equal "canceled", @membership.reload.status
    refute_predicate @membership, :active?
  end

  test "cancellation at period end keeps access until the paid period finishes" do
    subscription = create_subscription(membership: @membership, payment_option: @option,
                                       period_start: 1.month.ago, period_end: 10.days.from_now)

    result = PaymentEngine::Subscriptions::Cancel.call(subscription, immediately: false)

    assert_success(result)
    assert_equal :scheduled, result.code
    assert_predicate subscription.reload, :cancel_at_period_end?
    assert_equal "active", subscription.status
    assert_predicate @membership.reload, :active?
  end

  test "scheduling the same cancellation twice is idempotent" do
    subscription = create_subscription(membership: @membership, payment_option: @option)

    PaymentEngine::Subscriptions::Cancel.call(subscription)
    result = PaymentEngine::Subscriptions::Cancel.call(subscription)

    assert_success(result)
    assert_equal :already_scheduled, result.code
  end

  test "returns a controlled error when the provider cannot cancel subscriptions" do
    subscription = create_subscription(membership: @membership, payment_option: @option,
                                       provider: "limited", provider_subscription_id: "limited-sub")

    assert_failure(
      PaymentEngine::Subscriptions::Cancel.call(subscription),
      code: :unsupported_operation
    )
  end

  test "current returns the subscription of the owner's current membership" do
    subscription = create_subscription(membership: @membership, payment_option: @option)

    assert_equal subscription, PaymentEngine::Subscriptions::Current.call(@owner).data
    assert_nil PaymentEngine::Subscriptions::Current.call(create_owner).data
  end

  test "subscription keeps its commercial conditions when the option changes" do
    subscription = create_subscription(membership: @membership, payment_option: @option)

    @option.update!(price: 49_900, interval_count: 3)

    assert_equal 19_900, subscription.reload.effective_price
    assert_equal "COP", subscription.effective_currency
    assert_equal PaymentEngine::Duration.new(interval: "month", count: 1), subscription.duration_object
  end

  test "renew uses the subscription conditions instead of the current option price" do
    subscription = create_subscription(membership: @membership, payment_option: @option)
    @option.update!(price: 49_900)

    result = PaymentEngine::Subscriptions::Renew.call(subscription)

    assert_success(result)
    assert_equal 19_900, result.data[:purchase].amount
    assert_equal 19_900, result.data[:purchase].price
  end

  test "renew starts a payment attempt without extending access" do
    subscription = create_subscription(membership: @membership, payment_option: @option)
    original_expiration = @membership.expires_at

    result = PaymentEngine::Subscriptions::Renew.call(subscription)

    assert_success(result)
    assert_equal :renewal_started, result.code
    assert_equal original_expiration, @membership.reload.expires_at
    assert_equal "pending", result.data[:purchase].status
    assert_equal result.data[:purchase].id, result.data[:payment].purchase_id
  end

  test "renew reuses a pending renewal instead of creating another" do
    subscription = create_subscription(membership: @membership, payment_option: @option)

    first = PaymentEngine::Subscriptions::Renew.call(subscription)
    second = PaymentEngine::Subscriptions::Renew.call(subscription)

    assert_success(first)
    assert_success(second)
    assert_equal :renewal_pending, second.code
    assert_equal first.data[:purchase].id, second.data[:purchase].id
    assert_equal 1, PaymentEngine::Purchase.where(status: "pending").count
  end

  test "record renewal extends once and uses the billed period end" do
    subscription = create_subscription(membership: @membership, payment_option: @option,
                                       period_start: 1.month.ago, period_end: 10.days.from_now)
    @membership.update!(expires_at: subscription.current_period_ends_at)
    previous_expiration = @membership.expires_at

    result = PaymentEngine::Subscriptions::RecordRenewal.call(
      subscription: subscription,
      provider_transaction_id: "renewal-1",
      amount: 19_900,
      currency: "COP",
      period_starts_at: subscription.current_period_ends_at,
      period_ends_at: subscription.current_period_ends_at + 1.month
    )

    payment = assert_success(result).data
    assert_predicate payment, :approved?
    assert_equal "completed", payment.purchase.status
    assert_equal previous_expiration + 1.month, @membership.reload.expires_at
    assert_equal previous_expiration + 1.month, subscription.reload.current_period_ends_at
    assert_equal previous_expiration + 1.month, subscription.next_billing_at
  end

  test "record renewal does not extend twice for the same transaction" do
    subscription = create_subscription(membership: @membership, payment_option: @option)

    first = PaymentEngine::Subscriptions::RecordRenewal.call(
      subscription: subscription, provider_transaction_id: "renewal-duplicate",
      amount: 19_900, currency: "COP", period_ends_at: @membership.expires_at + 1.month
    )
    assert_success(first)
    expiration = @membership.reload.expires_at

    assert_no_difference -> { PaymentEngine::Payment.count } do
      second = PaymentEngine::Subscriptions::RecordRenewal.call(
        subscription: subscription, provider_transaction_id: "renewal-duplicate",
        amount: 19_900, currency: "COP", period_ends_at: expiration + 1.month
      )
      assert_success(second)
      assert_equal :already_processed, second.code
    end

    assert_equal expiration, @membership.reload.expires_at
  end

  test "record renewal rejects an amount that does not match the option" do
    subscription = create_subscription(membership: @membership, payment_option: @option)

    assert_failure(
      PaymentEngine::Subscriptions::RecordRenewal.call(
        subscription: subscription, provider_transaction_id: "renewal-wrong-amount",
        amount: 1_000, currency: "COP"
      ),
      code: :amount_mismatch
    )
    assert_equal 0, PaymentEngine::Payment.where(provider_transaction_id: "renewal-wrong-amount").count
  end

  test "record payment failure marks past due without removing access" do
    subscription = create_subscription(membership: @membership, payment_option: @option)

    result = PaymentEngine::Subscriptions::RecordPaymentFailure.call(
      subscription: subscription,
      provider_transaction_id: "failed-1",
      failure_reason: "insufficient funds"
    )

    payment = assert_success(result).data
    assert_equal "rejected", payment.status
    assert_equal "past_due", subscription.reload.status
    assert_predicate @membership.reload, :active?
  end

  test "grace period is applied once per billing period" do
    PaymentEngine.configure { |config| config.expiration_grace_period_days = 3 }
    subscription = create_subscription(membership: @membership, payment_option: @option,
                                       period_end: 10.days.from_now)
    @membership.update!(expires_at: subscription.current_period_ends_at)
    original_expiration = @membership.expires_at

    PaymentEngine::Subscriptions::RecordPaymentFailure.call(
      subscription: subscription, provider_transaction_id: "failed-grace-1"
    )
    assert_equal original_expiration + 3.days, @membership.reload.expires_at

    PaymentEngine::Subscriptions::RecordPaymentFailure.call(
      subscription: subscription, provider_transaction_id: "failed-grace-2"
    )
    assert_equal original_expiration + 3.days, @membership.reload.expires_at
  ensure
    PaymentEngine.configure { |config| config.expiration_grace_period_days = 0 }
  end

  test "provider cancellation at period end keeps access and schedules the end" do
    subscription = create_subscription(membership: @membership, payment_option: @option,
                                       period_end: 10.days.from_now)

    result = PaymentEngine::Subscriptions::ApplyProviderCancellation.call(subscription: subscription)

    assert_success(result)
    assert_equal :scheduled, result.code
    assert_predicate subscription.reload, :cancel_at_period_end?
    assert_predicate @membership.reload, :active?
  end

  test "provider cancellation after the period ends revokes access" do
    subscription = create_subscription(membership: @membership, payment_option: @option,
                                       period_start: 2.months.ago, period_end: 1.day.ago)

    result = PaymentEngine::Subscriptions::ApplyProviderCancellation.call(subscription: subscription)

    assert_success(result)
    assert_equal :canceled, result.code
    assert_equal "canceled", subscription.reload.status
    assert_equal "canceled", @membership.reload.status
  end
end
