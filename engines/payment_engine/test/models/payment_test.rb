require "test_helper"

class PaymentTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @purchase = create_purchase(owner: @owner)
  end

  test "exposes status predicates" do
    approved = create_payment(purchase: @purchase, status: "approved")
    refunded = create_payment(purchase: @purchase, status: "refunded")

    assert_predicate approved, :approved?
    assert_predicate approved, :final?
    assert_predicate refunded, :refunded?
  end

  test "prevents duplicated provider transactions" do
    create_payment(purchase: @purchase, provider_transaction_id: "txn-1")

    assert_raises(ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid) do
      create_payment(purchase: @purchase, provider_transaction_id: "txn-1")
    end
  end

  test "allows the same provider transaction id across different providers" do
    create_payment(purchase: @purchase, provider: "fake", provider_transaction_id: "shared")
    other = create_payment(purchase: @purchase, provider: "epayco", provider_transaction_id: "shared")

    assert_predicate other, :persisted?
  end

  test "requires a positive or zero amount and a currency" do
    payment = PaymentEngine::Payment.new(purchase: @purchase, provider: "fake",
                                         amount: -10, currency: "COP", status: "pending")

    refute payment.valid?
    assert payment.errors[:amount].any?
  end

  test "cannot delete a payment" do
    payment = create_payment(purchase: @purchase)

    refute payment.destroy
    assert PaymentEngine::Payment.exists?(payment.id)
  end
end
