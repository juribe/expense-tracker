require "test_helper"

class PaymentsConfirmTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @type = create_membership_type(slug: "premium")
    @option = create_payment_option(membership_type: @type, slug: "premium-monthly",
                                    price: 19_900, interval: "month", interval_count: 1)
  end

  test "approves the payment, completes the purchase and activates the membership" do
    travel_to Time.utc(2026, 1, 15, 9) do
      purchase = create_purchase(owner: @owner, payment_option: @option)
      payment = create_payment(purchase: purchase, provider_transaction_id: "txn-approved")

      result = PaymentEngine::Payments::Confirm.call(
        payment: payment,
        provider_transaction_id: "txn-approved",
        amount: 19_900,
        currency: "COP"
      )

      assert_success(result)
      payment.reload
      assert_predicate payment, :approved?
      assert_equal "completed", purchase.reload.status
      assert_equal purchase, payment.membership.purchases.first

      membership = payment.membership
      assert_equal Time.utc(2026, 1, 15, 9), membership.starts_at
      assert_equal Time.utc(2026, 2, 15, 9), membership.expires_at
      assert_predicate membership, :active?
      assert_equal @option, membership.payment_option
    end
  end

  test "is idempotent for an already approved payment" do
    purchase = create_purchase(owner: @owner, payment_option: @option)
    payment = create_payment(purchase: purchase, provider_transaction_id: "txn-idempotent")

    first = PaymentEngine::Payments::Confirm.call(payment: payment, provider_transaction_id: "txn-idempotent")
    assert_success(first)
    expiration = first.data.membership.expires_at

    assert_no_difference -> { PaymentEngine::Membership.count } do
      second = PaymentEngine::Payments::Confirm.call(payment: payment, provider_transaction_id: "txn-idempotent")
      assert_success(second)
      assert_equal :already_approved, second.code
    end

    assert_equal expiration, payment.reload.membership.expires_at
  end

  test "rejects an amount that does not match the purchase" do
    purchase = create_purchase(owner: @owner, payment_option: @option)
    payment = create_payment(purchase: purchase, provider_transaction_id: "txn-amount")

    result = PaymentEngine::Payments::Confirm.call(payment: payment, amount: 1_000)

    assert_failure(result, code: :amount_mismatch)
    assert_equal "pending", payment.reload.status
    assert_equal 0, PaymentEngine::Membership.count
  end

  test "rejects a currency that does not match the purchase" do
    purchase = create_purchase(owner: @owner, payment_option: @option)
    payment = create_payment(purchase: purchase, provider_transaction_id: "txn-currency")

    result = PaymentEngine::Payments::Confirm.call(payment: payment, currency: "USD")

    assert_failure(result, code: :amount_mismatch)
    assert_equal "pending", payment.reload.status
  end

  test "cannot approve a rejected payment" do
    purchase = create_purchase(owner: @owner, payment_option: @option)
    payment = create_payment(purchase: purchase, status: "rejected")

    assert_failure(
      PaymentEngine::Payments::Confirm.call(payment: payment),
      code: :invalid_state
    )
    assert_equal 0, PaymentEngine::Membership.count
  end

  test "a second payment does not extend a completed purchase" do
    purchase = create_purchase(owner: @owner, payment_option: @option)
    first = create_payment(purchase: purchase, provider_transaction_id: "txn-first")
    second = create_payment(purchase: purchase, provider_transaction_id: "txn-second")

    first_result = PaymentEngine::Payments::Confirm.call(payment: first, provider_transaction_id: "txn-first")
    assert_success(first_result)
    expiration = first_result.data.membership.expires_at

    second_result = PaymentEngine::Payments::Confirm.call(payment: second, provider_transaction_id: "txn-second")

    assert_success(second_result)
    assert_equal :already_completed, second_result.code
    assert_equal expiration, first_result.data.membership.reload.expires_at
    assert_equal 1, PaymentEngine::Membership.count
  end

  test "a renewal purchase extends the existing membership instead of creating another" do
    travel_to Time.utc(2026, 2, 1, 12) do
      membership = create_membership(owner: @owner, membership_type: @type,
                                     starts_at: 1.month.ago, expires_at: 10.days.from_now)
      purchase = create_purchase(owner: @owner, payment_option: @option, membership: membership,
                                 status: "pending")
      payment = create_payment(purchase: purchase, provider_transaction_id: "txn-renewal")

      assert_no_difference -> { PaymentEngine::Membership.count } do
        result = PaymentEngine::Payments::Confirm.call(payment: payment, provider_transaction_id: "txn-renewal")
        assert_success(result)
        assert_equal membership.id, result.data.membership.id
      end

      assert_equal Time.utc(2026, 2, 11, 12) + 1.month, membership.reload.expires_at
    end
  end

  test "returns a failure for a duplicated provider transaction" do
    first_purchase = create_purchase(owner: @owner, payment_option: @option)
    second_purchase = create_purchase(owner: @owner, payment_option: @option)
    create_payment(purchase: first_purchase, status: "approved", provider_transaction_id: "txn-duplicate")
    second_payment = create_payment(purchase: second_purchase, provider_transaction_id: nil)

    result = PaymentEngine::Payments::Confirm.call(
      payment: second_payment,
      provider_transaction_id: "txn-duplicate"
    )

    assert_failure(result, code: :duplicate_transaction)
    assert_equal "pending", second_payment.reload.status
  end

  test "requires a payment" do
    assert_failure(PaymentEngine::Payments::Confirm.call(payment: nil), code: :not_found)
  end
end
