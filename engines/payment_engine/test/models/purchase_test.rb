require "test_helper"

class PurchaseTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @type = create_membership_type(slug: "premium")
  end

  test "captures the commercial snapshot at creation" do
    option = create_payment_option(membership_type: @type, slug: "premium-annual", price: 199_000,
                                   billing_type: "recurring", interval: "year", interval_count: 1)
    purchase = create_purchase(owner: @owner, payment_option: option)

    assert_equal "premium annual", purchase.option_name.downcase
    assert_equal @type.name, purchase.membership_type_name
    assert_equal 199_000, purchase.price
    assert_equal 199_000, purchase.amount
    assert_equal "COP", purchase.currency
    assert_equal "recurring", purchase.billing_type
    assert_equal({ "interval" => "year", "count" => 1 }, purchase.duration)
    assert_equal PaymentEngine::Duration.new(interval: "year", count: 1), purchase.duration_object
  end

  test "rejects invalid statuses and negative amounts" do
    option = create_payment_option(membership_type: @type)
    purchase = PaymentEngine::Purchase.new(owner: @owner, payment_option: option,
                                           status: "unknown", amount: -1, currency: "COP")

    refute purchase.valid?
    assert purchase.errors[:status].any?
    assert purchase.errors[:amount].any?
  end

  test "persists the owning record and payment attempts" do
    purchase = create_purchase(owner: @owner)
    payment = create_payment(purchase: purchase)

    assert_equal @owner, purchase.owner
    assert_equal [ payment ], purchase.payments.to_a
  end

  test "cannot delete a purchase with payments" do
    purchase = create_purchase(owner: @owner)
    create_payment(purchase: purchase)

    refute purchase.destroy
    assert PaymentEngine::Purchase.exists?(purchase.id)
  end
end
