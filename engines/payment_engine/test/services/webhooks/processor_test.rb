require "test_helper"

class WebhooksProcessorTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @option = create_payment_option(slug: "premium-monthly")
  end

  test "processes a payment approval event exactly once" do
    purchase = create_purchase(owner: @owner, payment_option: @option)
    payment = create_payment(purchase: purchase, provider_transaction_id: "txn-webhook")
    event = event_for("payment.approved", provider_transaction_id: "txn-webhook",
                                           purchase_id: purchase.id, amount: purchase.amount,
                                           currency: purchase.currency)

    processed = PaymentEngine::Webhooks::Processor.call(event)

    assert_predicate processed, :processed?
    assert_predicate payment.reload, :approved?
    assert_equal "completed", purchase.reload.status
    assert_equal 1, PaymentEngine::Membership.count

    expiration = payment.membership.expires_at
    PaymentEngine::Webhooks::Processor.call(event.reload)
    assert_equal expiration, payment.membership.reload.expires_at
    assert_equal 1, PaymentEngine::Membership.count
  end

  test "ignores unknown event types" do
    event = event_for("unknown.event")

    PaymentEngine::Webhooks::Processor.call(event)
    assert_predicate event.reload, :ignored?
  end

  test "marks the event as failed and re-raises when the payment is missing" do
    event = event_for("payment.approved", provider_transaction_id: "does-not-exist")

    assert_raises(PaymentEngine::Webhooks::ProcessingError) do
      PaymentEngine::Webhooks::Processor.call(event)
    end

    assert_equal "failed", event.reload.status
    assert event.error_message.present?
  end

  test "records a rejected payment" do
    purchase = create_purchase(owner: @owner, payment_option: @option)
    payment = create_payment(purchase: purchase, provider_transaction_id: "txn-rejected")
    event = event_for("payment.rejected", provider_transaction_id: "txn-rejected",
                                          failure_reason: "declined")

    PaymentEngine::Webhooks::Processor.call(event)

    assert_equal "rejected", payment.reload.status
    assert_equal "failed", purchase.reload.status
    assert_predicate event.reload, :processed?
  end

  test "records a refund" do
    purchase = create_purchase(owner: @owner, payment_option: @option)
    payment = create_payment(purchase: purchase, provider_transaction_id: "txn-refund")
    PaymentEngine::Payments::Confirm.call(payment: payment, provider_transaction_id: "txn-refund")
    event = event_for("payment.refunded", provider_transaction_id: "txn-refund", amount: payment.amount)

    PaymentEngine::Webhooks::Processor.call(event)

    assert_equal "refunded", payment.reload.status
    assert_equal "canceled", payment.membership.reload.status
  end

  test "records a subscription renewal without double extension" do
    membership = create_membership(owner: @owner, payment_option: @option,
                                   expires_at: 1.month.from_now)
    subscription = create_subscription(membership: membership, payment_option: @option,
                                       period_end: membership.expires_at)
    event = event_for("subscription.renewed",
                      subscription_id: subscription.id,
                      provider_transaction_id: "renewal-webhook",
                      amount: @option.price,
                      currency: @option.currency,
                      period_starts_at: membership.expires_at,
                      period_ends_at: membership.expires_at + 1.month)
    expected_expiration = membership.expires_at + 1.month

    PaymentEngine::Webhooks::Processor.call(event)
    PaymentEngine::Webhooks::Processor.call(event.reload)

    assert_equal expected_expiration.to_i, membership.reload.expires_at.to_i
    assert_equal 1, PaymentEngine::Payment.where(provider_transaction_id: "renewal-webhook").count
  end

  private

  def event_for(event_type, data = {})
    create_webhook_event(
      event_type: event_type,
      payload: { "_payment_engine" => data.merge(event_type: event_type) }
    )
  end
end
