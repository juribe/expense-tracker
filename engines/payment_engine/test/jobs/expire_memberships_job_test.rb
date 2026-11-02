require "test_helper"

class ExpireMembershipsJobTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @option = create_payment_option(slug: "premium-monthly")
  end

  test "expires memberships whose period has ended" do
    expired = create_membership(owner: @owner, membership_type: @option.membership_type,
                                status: "active", starts_at: 2.months.ago, expires_at: 1.day.ago)

    result = PaymentEngine::Jobs::ExpireMembershipsJob.perform_now

    assert_equal 1, result[:memberships_expired]
    assert_equal "expired", expired.reload.status
    refute_predicate expired, :active?
  end

  test "keeps current memberships untouched" do
    active = create_membership(owner: @owner, membership_type: @option.membership_type,
                               starts_at: 1.day.ago, expires_at: 1.month.from_now)

    result = PaymentEngine::Jobs::ExpireMembershipsJob.perform_now

    assert_equal 0, result[:memberships_expired]
    assert_equal "active", active.reload.status
  end

  test "finalizes cancellations scheduled at period end" do
    membership = create_membership(owner: @owner, membership_type: @option.membership_type,
                                   starts_at: 2.months.ago, expires_at: 1.day.ago)
    subscription = create_subscription(membership: membership, payment_option: @option,
                                       period_start: 2.months.ago, period_end: 1.day.ago,
                                       cancel_at_period_end: true)

    result = PaymentEngine::Jobs::ExpireMembershipsJob.perform_now

    assert_equal 1, result[:subscriptions_canceled]
    assert_equal "canceled", subscription.reload.status
    assert_equal "canceled", membership.reload.status
    refute_predicate subscription, :cancel_at_period_end?
  end

  test "expires subscriptions whose period has ended" do
    membership = create_membership(owner: @owner, membership_type: @option.membership_type,
                                   starts_at: 2.months.ago, expires_at: 1.day.ago)
    subscription = create_subscription(membership: membership, payment_option: @option,
                                       period_start: 2.months.ago, period_end: 1.day.ago)

    result = PaymentEngine::Jobs::ExpireMembershipsJob.perform_now

    assert_equal 1, result[:subscriptions_expired]
    assert_equal "expired", subscription.reload.status
    assert_equal "expired", membership.reload.status
  end

  test "is idempotent across repeated executions" do
    create_membership(owner: @owner, membership_type: @option.membership_type,
                      starts_at: 2.months.ago, expires_at: 1.day.ago)

    first = PaymentEngine::Jobs::ExpireMembershipsJob.perform_now
    second = PaymentEngine::Jobs::ExpireMembershipsJob.perform_now

    assert_equal 1, first[:memberships_expired]
    assert_equal 0, second[:memberships_expired]
    assert_equal 0, second[:subscriptions_canceled]
    assert_equal 0, second[:subscriptions_expired]
  end
end
