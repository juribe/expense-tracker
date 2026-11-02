require "test_helper"

class MembershipsGrantTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @type = create_membership_type(slug: "premium")
    @option = create_payment_option(membership_type: @type)
  end

  test "creates an active membership using calendar duration" do
    travel_to Time.utc(2026, 1, 31, 10) do
      result = PaymentEngine::Memberships::Grant.call(
        owner: @owner,
        membership_type: @type,
        payment_option: @option,
        duration: PaymentEngine::Duration.new(interval: "month", count: 1)
      )

      membership = assert_success(result).data
      assert_equal Time.utc(2026, 1, 31, 10), membership.starts_at
      assert_equal Time.utc(2026, 2, 28, 10), membership.expires_at
      assert_predicate membership, :active?
      assert_equal @option, membership.payment_option
    end
  end

  test "extends from the current expiration, not from now" do
    membership = create_membership(owner: @owner, membership_type: @type,
                                   starts_at: 1.month.ago, expires_at: 10.days.from_now)
    original_expiration = membership.expires_at

    result = PaymentEngine::Memberships::Grant.call(
      owner: @owner,
      membership_type: @type,
      duration: PaymentEngine::Duration.new(interval: "month", count: 1)
    )

    assert_success(result)
    assert_equal original_expiration + 1.month, membership.reload.expires_at
  end

  test "extends an expired membership from now" do
    travel_to Time.utc(2026, 3, 15, 12) do
      membership = create_membership(owner: @owner, membership_type: @type,
                                     starts_at: 3.months.ago, expires_at: 1.month.ago)

      PaymentEngine::Memberships::Grant.call(
        owner: @owner,
        membership_type: @type,
        duration: PaymentEngine::Duration.new(interval: "month", count: 1)
      )

      assert_equal Time.utc(2026, 4, 15, 12), membership.reload.expires_at
    end
  end

  test "reuses the open membership instead of creating a duplicate" do
    duration = PaymentEngine::Duration.new(interval: "month", count: 1)

    assert_difference -> { PaymentEngine::Membership.count }, 1 do
      PaymentEngine::Memberships::Grant.call(owner: @owner, membership_type: @type, duration: duration)
      PaymentEngine::Memberships::Grant.call(owner: @owner, membership_type: @type, duration: duration)
    end
  end

  test "reactivates an expired membership passed explicitly without a new row" do
    membership = create_membership(owner: @owner, membership_type: @type, status: "expired",
                                   starts_at: 2.months.ago, expires_at: 1.month.ago)

    result = nil
    assert_no_difference -> { PaymentEngine::Membership.count } do
      result = PaymentEngine::Memberships::Grant.call(
        owner: @owner,
        membership_type: @type,
        membership: membership,
        duration: PaymentEngine::Duration.new(interval: "year", count: 1)
      )
    end

    assert_success(result)
    assert_equal "active", membership.reload.status
    assert_operator membership.expires_at, :>, Time.current
  end

  test "supports simultaneous different membership types" do
    pro = create_membership_type(slug: "pro")
    duration = PaymentEngine::Duration.new(interval: "month", count: 1)

    PaymentEngine::Memberships::Grant.call(owner: @owner, membership_type: @type, duration: duration)
    PaymentEngine::Memberships::Grant.call(owner: @owner, membership_type: pro, duration: duration)

    assert PaymentEngine::Membership.active?(@owner, type: "premium")
    assert PaymentEngine::Membership.active?(@owner, type: "pro")
  end

  test "creates trialing memberships" do
    result = PaymentEngine::Memberships::Grant.call(
      owner: @owner,
      membership_type: @type,
      duration: PaymentEngine::Duration.new(interval: "day", count: 14),
      status: "trialing"
    )

    membership = assert_success(result).data
    assert_predicate membership, :trialing?
    assert_predicate membership, :active?
  end

  test "grants an indefinite free membership without a payment" do
    result = PaymentEngine::Memberships::Grant.call(
      owner: @owner,
      membership_type: @type,
      expires_at: nil,
      metadata: { "source" => "admin" }
    )

    membership = assert_success(result).data
    assert_nil membership.expires_at
    assert_nil membership.days_remaining
    assert_predicate membership, :active?
  end

  test "rejects missing arguments" do
    assert_failure(
      PaymentEngine::Memberships::Grant.call(owner: @owner, membership_type: @type, duration: nil),
      code: :invalid_argument
    )
    assert_failure(
      PaymentEngine::Memberships::Grant.call(owner: nil, membership_type: @type,
                                             duration: PaymentEngine::Duration.new(interval: "month")),
      code: :invalid_argument
    )
  end
end
