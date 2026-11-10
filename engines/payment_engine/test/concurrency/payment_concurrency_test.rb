require "test_helper"

class PaymentConcurrencyTest < PaymentEngineTestCase
  self.use_transactional_tests = false

  setup do
    PaymentEngine::Events.reset!
    cleanup_records
  end

  teardown do
    cleanup_records
    PaymentEngine::Events.reset!
  end

  test "concurrent confirmations of the same payment extend access once" do
    owner = create_owner
    option = create_payment_option(slug: "premium-monthly")
    purchase = create_purchase(owner: owner, payment_option: option)
    payment = create_payment(purchase: purchase, provider_transaction_id: "concurrent-txn")
    payment_id = payment.id

    results = run_concurrently(2) do
      PaymentEngine::Payments::Confirm.call(
        payment: PaymentEngine::Payment.find(payment_id),
        provider_transaction_id: "concurrent-txn"
      )
    end

    assert_equal 2, results.size
    assert results.all?(&:success?), results.map(&:errors).inspect
    payment.reload
    assert_predicate payment, :approved?
    assert_equal 1, PaymentEngine::Membership.count
    membership = PaymentEngine::Membership.first
    assert_equal membership.starts_at + 1.month, membership.expires_at
  end

  test "concurrent purchases for the same option create only one pending purchase" do
    owner = create_owner
    option = create_payment_option(slug: "premium-monthly")
    owner_id = owner.id
    option_id = option.id

    results = run_concurrently(2) do
      PaymentEngine::Purchases::Create.call(
        owner: User.find(owner_id),
        payment_option: PaymentEngine::PaymentOption.find(option_id)
      )
    end

    assert_equal 1, results.count(&:success?)
    assert_equal 1, results.count { |result| result.code == :duplicate_purchase }
    assert_equal 1, PaymentEngine::Purchase.count
  end

  private

  def run_concurrently(threads)
    barrier = Queue.new
    results = Queue.new

    workers = threads.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          results << yield
        end
      end
    end

    threads.times { barrier << true }
    workers.each(&:join)

    threads.times.map { results.pop }
  end

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
