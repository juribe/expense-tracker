require "test_helper"

class WebhooksEndpointTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SECRET = "test-webhook-secret".freeze

  test "accepts a valid webhook, stores it and enqueues processing" do
    assert_difference -> { PaymentEngine::WebhookEvent.count }, 1 do
      assert_enqueued_with(job: PaymentEngine::Webhooks::ProcessJob) do
        post "/payment_engine/webhooks/fake",
             params: { event_id: "evt-http-1", event_type: "payment.approved",
                       data: { provider_transaction_id: "txn-http" } },
             headers: { "X-Fake-Signature" => SECRET }
      end
    end

    assert_response :ok
  end

  test "rejects invalid signatures" do
    assert_no_difference -> { PaymentEngine::WebhookEvent.count } do
      post "/payment_engine/webhooks/fake",
           params: { event_id: "evt-http-2", event_type: "payment.approved" },
           headers: { "X-Fake-Signature" => "invalid" }
    end

    assert_response :unauthorized
  end

  test "returns not found for unknown providers" do
    post "/payment_engine/webhooks/nope",
         params: { event_id: "evt-http-3", event_type: "payment.approved" },
         headers: { "X-Fake-Signature" => SECRET }

    assert_response :not_found
  end

  test "acknowledges duplicate deliveries without creating another event" do
    params = { event_id: "evt-http-4", event_type: "payment.approved" }
    post "/payment_engine/webhooks/fake", params: params, headers: { "X-Fake-Signature" => SECRET }
    assert_response :ok

    assert_no_difference -> { PaymentEngine::WebhookEvent.count } do
      post "/payment_engine/webhooks/fake", params: params, headers: { "X-Fake-Signature" => SECRET }
    end

    assert_response :ok
  end
end
