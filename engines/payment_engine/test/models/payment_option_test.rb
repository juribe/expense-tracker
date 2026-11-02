require "test_helper"

class PaymentOptionTest < PaymentEngineTestCase
  test "exposes one time and recurring predicates" do
    one_time = create_payment_option(slug: "monthly", billing_type: "one_time")
    recurring = create_payment_option(slug: "monthly-auto", billing_type: "recurring")

    assert_predicate one_time, :one_time?
    refute_predicate one_time, :recurring?
    assert_predicate recurring, :recurring?
    refute_predicate recurring, :one_time?
  end

  test "duration represents months and years without fixed seconds" do
    quarterly = create_payment_option(slug: "quarterly", interval: "month", interval_count: 3)
    annual = create_payment_option(slug: "annual", interval: "year", interval_count: 1)

    assert_equal({ "interval" => "month", "count" => 3 }, quarterly.duration.to_h)
    assert_equal({ "interval" => "year", "count" => 1 }, annual.duration.to_h)
    assert_equal Date.new(2026, 4, 30), quarterly.duration.apply_to(Date.new(2026, 1, 30))
  end

  test "rejects negative prices" do
    option = PaymentEngine::PaymentOption.new(
      membership_type: create_membership_type, name: "Invalid", slug: "invalid",
      price: -1, currency: "COP", billing_type: "one_time"
    )

    refute option.valid?
    assert_includes option.errors[:price], "must be greater than or equal to 0"
  end

  test "requires an explicit ISO currency" do
    option = PaymentEngine::PaymentOption.new(
      membership_type: create_membership_type, name: "Invalid", slug: "invalid-currency",
      price: 100, currency: "pesos", billing_type: "one_time"
    )

    refute option.valid?
    assert option.errors[:currency].any?
  end

  test "recurring options require a valid interval" do
    option = PaymentEngine::PaymentOption.new(
      membership_type: create_membership_type, name: "Recurring", slug: "recurring-without-interval",
      price: 100, currency: "COP", billing_type: "recurring", interval: nil
    )

    refute option.valid?
    assert option.errors[:interval].any?
  end

  test "for returns only active options of the requested type" do
    type = create_membership_type(slug: "premium")
    active = create_payment_option(membership_type: type, slug: "premium-monthly")
    create_payment_option(membership_type: type, slug: "premium-inactive", active: false)
    other_type = create_membership_type(slug: "basic")
    create_payment_option(membership_type: other_type, slug: "basic-monthly")

    assert_equal [ active ], PaymentEngine::PaymentOption.for("premium").to_a
  end

  test "find_by_slug excludes inactive options by default" do
    create_payment_option(slug: "premium-monthly", active: false)

    assert_nil PaymentEngine::PaymentOption.find_by_slug("premium-monthly")
    assert PaymentEngine::PaymentOption.find_by_slug("premium-monthly", active_only: false)
  end

  test "price changes do not modify existing purchases" do
    option = create_payment_option(slug: "premium-monthly", price: 19_900)
    purchase = create_purchase(owner: create_owner, payment_option: option)

    option.update!(price: 29_900)

    assert_equal 19_900, purchase.reload.price
    assert_equal 19_900, purchase.amount
  end

  test "cannot delete an option with purchases" do
    option = create_payment_option(slug: "premium-monthly")
    create_purchase(owner: create_owner, payment_option: option)

    refute option.destroy
    assert PaymentEngine::PaymentOption.exists?(option.id)
  end
end
