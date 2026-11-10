require "test_helper"

class WebhookEventTest < PaymentEngineTestCase
  test "event ids are unique per provider" do
    create_webhook_event(provider: "fake", event_id: "evt-1")
    create_webhook_event(provider: "epayco", event_id: "evt-1")

    assert_raises(ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid) do
      create_webhook_event(provider: "fake", event_id: "evt-1")
    end
  end

  test "state transitions are explicit and idempotent" do
    event = create_webhook_event(status: "received")

    event.mark_processing!
    assert_equal "processing", event.status
    assert_equal 1, event.attempts

    event.mark_processed!
    assert_predicate event, :processed?
    assert event.processed_at.present?

    event.mark_ignored!("unknown")
    assert_predicate event, :ignored?

    event.mark_failed!("boom")
    assert_equal "failed", event.status
    assert_equal "boom", event.error_message
  end
end
