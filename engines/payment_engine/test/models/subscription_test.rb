require "test_helper"

class SubscriptionTest < PaymentEngineTestCase
  setup do
    @membership = create_membership(owner: create_owner)
    @option = create_payment_option(membership_type: @membership.membership_type,
                                    billing_type: "recurring")
  end

  test "active? combines status and billed period" do
    active = create_subscription(membership: @membership, payment_option: @option, period_end: 1.month.from_now)
    expired_period = create_subscription(membership: @membership, payment_option: @option,
                                         period_start: 2.months.ago, period_end: 1.day.ago)

    assert_predicate active, :active?
    refute_predicate expired_period, :active?
  end

  test "cancel_at_period_end? reflects the stored flag" do
    subscription = create_subscription(membership: @membership, payment_option: @option,
                                       cancel_at_period_end: true)

    assert_predicate subscription, :cancel_at_period_end?
  end

  test "provider subscription id is unique per provider" do
    create_subscription(membership: @membership, payment_option: @option, provider_subscription_id: "sub-1")

    assert_raises(ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid) do
      create_subscription(membership: @membership, payment_option: @option, provider_subscription_id: "sub-1")
    end
  end

  test "renewal_due? requires an active subscription and a reached billing date" do
    due = create_subscription(membership: @membership, payment_option: @option,
                              next_billing_at: 1.hour.ago, period_end: 1.month.from_now)
    not_due = create_subscription(membership: @membership, payment_option: @option,
                                  next_billing_at: 1.month.from_now, period_end: 2.months.from_now)

    assert_predicate due, :renewal_due?
    refute_predicate not_due, :renewal_due?
  end
end
