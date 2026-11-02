require "test_helper"

class PaymentsRefundTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @option = create_payment_option(slug: "premium-monthly")
    @purchase = create_purchase(owner: @owner, payment_option: @option)
  end

  test "a full refund revokes access and records the refund" do
    payment, membership = approved_payment_with_membership
    subscription = create_subscription(membership: membership, payment_option: @option)

    result = PaymentEngine::Payments::Refund.call(payment: payment, reason: "customer request")

    assert_success(result)
    assert_equal "refunded", payment.reload.status
    assert_equal "refunded", @purchase.reload.status
    assert_equal "canceled", membership.reload.status
    assert_equal "canceled", subscription.reload.status
  end

  test "a partial refund keeps access" do
    payment, membership = approved_payment_with_membership

    result = PaymentEngine::Payments::Refund.call(payment: payment, amount: 5_000)

    assert_success(result)
    assert_equal "partially_refunded", payment.reload.status
    assert_predicate membership.reload, :active?
  end

  test "refunds are idempotent" do
    payment, = approved_payment_with_membership

    PaymentEngine::Payments::Refund.call(payment: payment)
    result = PaymentEngine::Payments::Refund.call(payment: payment)

    assert_success(result)
    assert_equal :already_refunded, result.code
  end

  test "only approved payments can be refunded" do
    payment = create_payment(purchase: @purchase, status: "pending")

    assert_failure(PaymentEngine::Payments::Refund.call(payment: payment), code: :invalid_state)
  end

  test "access is kept when the host disables revocation on refund" do
    payment, membership = approved_payment_with_membership
    PaymentEngine.configure { |config| config.revoke_access_on_refund = false }

    assert_success(PaymentEngine::Payments::Refund.call(payment: payment))

    assert_predicate membership.reload, :active?
  ensure
    PaymentEngine.configure { |config| config.revoke_access_on_refund = true }
  end

  private

  def approved_payment_with_membership
    payment = create_payment(purchase: @purchase, provider_transaction_id: "txn-#{SecureRandom.hex(4)}")
    result = PaymentEngine::Payments::Confirm.call(payment: payment, provider_transaction_id: payment.provider_transaction_id)
    assert_success(result)

    [ payment.reload, result.data.membership ]
  end
end
