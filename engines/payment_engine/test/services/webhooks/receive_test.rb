require "test_helper"

class WebhooksReceiveTest < PaymentEngineTestCase
  SECRET = "test-webhook-secret".freeze

  def headers(signature: SECRET)
    { "X-Fake-Signature" => signature }
  end

  def payload(event_id: "evt-1", event_type: "payment.approved", data: {})
    { event_id: event_id, event_type: event_type, data: data }
  end

  test "validates the signature and stores the event once" do
    assert_difference -> { PaymentEngine::WebhookEvent.count }, 1 do
      assert_enqueued_with(job: PaymentEngine::Webhooks::ProcessJob) do
        result = PaymentEngine::Webhooks::Receive.call(
          provider_name: "fake",
          payload: payload(data: { provider_transaction_id: "txn-1" }),
          headers: headers
        )

        assert_success(result)
        assert_equal :received, result.code
        assert_equal "payment.approved", result.data.event_type
      end
    end
  end

  test "rejects an invalid signature without persisting anything" do
    assert_no_difference -> { PaymentEngine::WebhookEvent.count } do
      result = PaymentEngine::Webhooks::Receive.call(
        provider_name: "fake",
        payload: payload,
        headers: headers(signature: "wrong")
      )

      assert_failure(result, code: :invalid_signature)
    end
  end

  test "duplicate events are not persisted or enqueued twice" do
    PaymentEngine::Webhooks::Receive.call(provider_name: "fake", payload: payload, headers: headers)

    assert_no_difference -> { PaymentEngine::WebhookEvent.count } do
      assert_no_enqueued_jobs do
        result = PaymentEngine::Webhooks::Receive.call(provider_name: "fake", payload: payload, headers: headers)

        assert_success(result)
        assert_equal :duplicate, result.code
      end
    end
  end

  test "redacts sensitive fields before persisting the payload" do
    result = PaymentEngine::Webhooks::Receive.call(
      provider_name: "fake",
      payload: payload(data: { card_number: "4111111111111111", nested: { cvv: "123", token: "secret" } }),
      headers: headers
    )

    event = assert_success(result).data
    assert_equal "[FILTERED]", event.payload.dig("data", "card_number")
    assert_equal "[FILTERED]", event.payload.dig("data", "nested", "cvv")
    assert_equal "[FILTERED]", event.payload.dig("data", "nested", "token")
    assert_equal "[FILTERED]", event.payload.dig("_payment_engine", "card_number")
  end

  test "rejects unknown providers" do
    assert_failure(
      PaymentEngine::Webhooks::Receive.call(provider_name: "unknown", payload: payload, headers: headers),
      code: :unknown_provider
    )
  end

  test "rejects malformed events without a type" do
    result = PaymentEngine::Webhooks::Receive.call(
      provider_name: "fake",
      payload: { event_id: "evt-malformed" },
      headers: headers
    )

    assert_failure(result, code: :malformed_event)
  end
end
