require "test_helper"

class PurchasesCreateTest < PaymentEngineTestCase
  setup do
    @owner = create_owner
    @type = create_membership_type(slug: "premium")
    @option = create_payment_option(membership_type: @type, slug: "premium-monthly")
  end

  test "creates a purchase and a pending payment without activating a membership" do
    result = PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: @option, provider: :fake)

    data = assert_success(result).data
    purchase = data[:purchase]
    payment = data[:payment]

    assert_equal "pending", purchase.status
    assert_equal 19_900, purchase.amount
    assert_equal "COP", purchase.currency
    assert_equal "pending", payment.status
    assert payment.provider_transaction_id.present?
    assert_equal "https://fake.payment.test/checkout/#{purchase.id}", data[:checkout][:url]
    assert_equal 0, PaymentEngine::Membership.where(owner: @owner).count
  end

  test "rejects inactive payment options" do
    @option.update!(active: false)

    assert_failure(
      PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: @option),
      code: :inactive_option
    )
    assert_equal 0, PaymentEngine::Purchase.count
  end

  test "rejects inactive membership types" do
    @type.update!(active: false)

    assert_failure(
      PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: @option),
      code: :inactive_membership_type
    )
  end

  test "rejects a duplicated purchase while another one is in progress" do
    PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: @option)
    result = PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: @option)

    assert_failure(result, code: :duplicate_purchase)
    assert_equal 1, PaymentEngine::Purchase.count
  end

  test "rejects recurring options when the provider lacks recurring support" do
    recurring = create_payment_option(membership_type: @type, slug: "premium-auto",
                                      billing_type: "recurring")

    result = PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: recurring, provider: :limited)

    assert_failure(result, code: :unsupported_operation)
    assert_equal 0, PaymentEngine::Purchase.count
  end

  test "marks the purchase as failed when the provider declines" do
    result = PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: @option, provider: :failing)

    assert_failure(result, code: :provider_declined)
    assert_equal "failed", result.data[:purchase].status
    assert_equal "rejected", result.data[:payment].status
    assert_equal "provider declined the operation", result.data[:payment].failure_reason
  end

  test "returns a controlled error when the provider raises" do
    result = PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: @option, provider: :raising)

    assert_failure(result, code: :provider_error)
    assert_equal 0, PaymentEngine::Membership.count
  end

  test "requires a persisted owner" do
    unsaved = User.new(name: "New", email: "new@example.com")

    assert_failure(
      PaymentEngine::Purchases::Create.call(owner: unsaved, payment_option: @option),
      code: :invalid_owner
    )
  end

  test "uses the configured default provider" do
    result = PaymentEngine::Purchases::Create.call(owner: @owner, payment_option: @option)

    assert_success(result)
    assert_equal "fake", result.data[:purchase].provider
  end
end
