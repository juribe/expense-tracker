require "test_helper"

class EventsTest < PaymentEngineTestCase
  self.use_transactional_tests = false

  setup do
    PaymentEngine::Events.reset!
    cleanup_records
  end

  teardown do
    cleanup_records
    PaymentEngine::Events.reset!
  end

  test "host callbacks receive published events" do
    received = []
    PaymentEngine.on(:membership_activated) { |event| received << event }

    owner = create_owner
    type = create_membership_type(slug: "premium")

    PaymentEngine::Memberships::Grant.call(
      owner: owner, membership_type: type,
      duration: PaymentEngine::Duration.new(interval: "month")
    )

    assert_equal 1, received.size
    assert_equal :membership_activated, received.first.name
    assert_equal owner, received.first[:owner]
  end

  test "a failing host callback does not break the financial operation" do
    PaymentEngine.on(:membership_activated) { |_event| raise "host integration exploded" }

    result = PaymentEngine::Memberships::Grant.call(
      owner: create_owner, membership_type: create_membership_type(slug: "premium"),
      duration: PaymentEngine::Duration.new(interval: "month")
    )

    assert_success(result)
    assert_equal 1, PaymentEngine::Membership.count
  end

  test "events are not published when the transaction rolls back" do
    received = []
    PaymentEngine.on(:membership_activated) { |event| received << event }
    owner = create_owner
    type = create_membership_type(slug: "premium")

    ActiveRecord::Base.transaction do
      PaymentEngine::Memberships::Grant.call(
        owner: owner, membership_type: type,
        duration: PaymentEngine::Duration.new(interval: "month")
      )
      raise ActiveRecord::Rollback
    end

    assert_empty received
    assert_equal 0, PaymentEngine::Membership.count
  end

  test "rejects unknown event names" do
    assert_raises(ArgumentError) { PaymentEngine.on(:unknown_event) { } }
  end

  private

  def cleanup_records
    PaymentEngine::Payment.delete_all
    PaymentEngine::Purchase.delete_all
    PaymentEngine::Subscription.delete_all
    PaymentEngine::Membership.delete_all
    PaymentEngine::ProviderCustomer.delete_all
    PaymentEngine::WebhookEvent.delete_all
    PaymentEngine::PaymentOption.delete_all
    PaymentEngine::MembershipType.delete_all
    User.delete_all
  end
end
