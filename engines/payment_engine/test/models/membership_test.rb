require "test_helper"

class MembershipTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @type = create_membership_type(slug: "premium")
  end

  test "active? requires an access status and valid dates" do
    membership = create_membership(owner: @owner, membership_type: @type, status: "active",
                                   starts_at: 1.day.ago, expires_at: 1.day.from_now)

    assert_predicate membership, :active?
  end

  test "expired by date is inactive even when status is still active" do
    membership = create_membership(owner: @owner, membership_type: @type, status: "active",
                                   starts_at: 2.months.ago, expires_at: 1.day.ago)

    refute_predicate membership, :active?
    assert_predicate membership, :expired?
    refute PaymentEngine::Membership.active?(@owner)
  end

  test "future memberships are not active yet" do
    membership = create_membership(owner: @owner, membership_type: @type, status: "active",
                                   starts_at: 1.day.from_now, expires_at: 1.month.from_now)

    refute_predicate membership, :active?
  end

  test "pending and canceled memberships never grant access" do
    pending = create_membership(owner: @owner, membership_type: @type, status: "pending")
    canceled = create_membership(owner: @owner, membership_type: @type, status: "canceled",
                                 starts_at: 1.month.ago, expires_at: 1.month.from_now)

    refute_predicate pending, :active?
    refute_predicate canceled, :active?
    assert_predicate canceled, :canceled?
  end

  test "trialing memberships grant access" do
    membership = create_membership(owner: @owner, membership_type: @type, status: "trialing",
                                   starts_at: 1.day.ago, expires_at: 5.days.from_now)

    assert_predicate membership, :active?
    assert_predicate membership, :trialing?
    assert PaymentEngine::Membership.active?(@owner)
  end

  test "indefinite memberships remain active without an expiration" do
    membership = create_membership(owner: @owner, membership_type: @type, expires_at: nil)

    assert_predicate membership, :active?
    assert_nil membership.days_remaining
    assert_nil membership.expires_in
  end

  test "days remaining counts complete days left" do
    travel_to Time.utc(2026, 2, 1, 12, 0, 0) do
      membership = create_membership(owner: @owner, membership_type: @type,
                                     starts_at: 1.day.ago, expires_at: 10.days.from_now + 6.hours)

      assert_equal 10, membership.days_remaining
      assert_equal 10.days.to_i + 6.hours.to_i, membership.expires_in
      assert_kind_of ActiveSupport::Duration, membership.remaining_time
    end
  end

  test "expiring soon uses the requested window" do
    travel_to Time.utc(2026, 2, 1, 12, 0, 0) do
      membership = create_membership(owner: @owner, membership_type: @type,
                                     starts_at: 1.month.ago, expires_at: 5.days.from_now)

      assert_predicate membership, :expiring_soon?
      assert membership.expiring_soon?(days: 7)
      refute membership.expiring_soon?(days: 3)
      assert PaymentEngine::Membership.expiring_soon?(@owner, days: 7)
    end
  end

  test "current selects active before trialing and then the latest expiration" do
    trialing = create_membership(owner: @owner, membership_type: @type, status: "trialing",
                                 starts_at: 1.day.ago, expires_at: 1.year.from_now)
    active = create_membership(owner: @owner, membership_type: create_membership_type(slug: "pro"),
                               status: "active", starts_at: 2.days.ago, expires_at: 1.month.from_now)

    assert_equal active, PaymentEngine::Membership.current(@owner)
    assert_equal active.membership_type, PaymentEngine::Membership.current_type(@owner)
    assert_equal active.expires_at, PaymentEngine::Membership.expires_at(@owner)
    assert_equal active.days_remaining, PaymentEngine::Membership.days_remaining(@owner)
    assert_equal [ active, trialing ].sort_by(&:id), PaymentEngine::Membership.all_active(@owner).sort_by(&:id)
  end

  test "queries can be scoped by membership type slug" do
    premium = create_membership(owner: @owner, membership_type: @type, expires_at: 1.month.from_now)
    basic_type = create_membership_type(slug: "basic")
    create_membership(owner: @owner, membership_type: basic_type, expires_at: 2.months.from_now)

    assert PaymentEngine::Membership.active?(@owner, type: "premium")
    assert_equal premium, PaymentEngine::Membership.current(@owner, type: "premium")
    assert PaymentEngine::Membership.has_type?(@owner, slug: "premium")
    refute PaymentEngine::Membership.has_type?(@owner, slug: "enterprise")
    assert_equal 2, PaymentEngine::Membership.all_active(@owner).count
  end

  test "has_type? can include inactive historical memberships" do
    create_membership(owner: @owner, membership_type: @type, status: "expired",
                      starts_at: 2.months.ago, expires_at: 1.month.ago)

    refute PaymentEngine::Membership.has_type?(@owner, slug: "premium")
    assert PaymentEngine::Membership.has_type?(@owner, slug: "premium", active_only: false)
  end

  test "an owner can hold different simultaneous membership types" do
    pro = create_membership_type(slug: "pro")
    create_membership(owner: @owner, membership_type: @type, expires_at: 1.month.from_now)
    create_membership(owner: @owner, membership_type: pro, expires_at: 1.month.from_now)

    assert PaymentEngine::Membership.active?(@owner, type: "premium")
    assert PaymentEngine::Membership.active?(@owner, type: "pro")
  end

  test "the database prevents two open memberships for the same owner and type" do
    create_membership(owner: @owner, membership_type: @type, expires_at: 1.month.from_now)

    assert_raises(ActiveRecord::RecordNotUnique) do
      create_membership(owner: @owner, membership_type: @type, expires_at: 2.months.from_now)
    end
  end

  test "rejects an expiration before the start date" do
    membership = PaymentEngine::Membership.new(
      owner: @owner, membership_type: @type, status: "active",
      starts_at: 1.day.from_now, expires_at: 1.day.ago
    )

    refute membership.valid?
    assert membership.errors[:expires_at].any?
  end

  test "exposes the current subscription" do
    membership = create_membership(owner: @owner, membership_type: @type)
    subscription = create_subscription(membership: membership)

    assert_equal subscription, membership.subscription
  end
end
