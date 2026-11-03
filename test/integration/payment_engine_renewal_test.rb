require "test_helper"
require "digest"

# Covers the early-renewal rule: remaining subscription time is preserved.
class PaymentEngineRenewalTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @customer_id = "123456"
    @p_key = "test-p-key"

    @provider = PaymentEngine::Provider.find_or_create_by!(code: "epayco") do |p|
      p.name = "ePayco"
      p.active = true
      p.environment = "sandbox"
    end
    @provider.update!(
      credentials: { customer_id: @customer_id, p_key: @p_key },
      settings: {}
    )

    @membership_type = PaymentEngine::MembershipType.find_or_create_by!(code: "EPAYCO_RENEW") { |mt| mt.name = "Epayco Renew"; mt.status = "active" }
    @monthly = PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @membership_type, name: "Mensual Renew") do |po|
      po.price = 14_900
      po.currency = "COP"
      po.mode = "recurring"
      po.interval = "month"
      po.interval_count = 1
      po.access_duration_count = 1
      po.access_duration_unit = "month"
      po.status = "active"
    end
    @annual = PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @membership_type, name: "Anual Renew") do |po|
      po.price = 149_900
      po.currency = "COP"
      po.mode = "one_time"
      po.access_duration_count = 12
      po.access_duration_unit = "month"
      po.status = "active"
    end

    @owner = User.create!(email: "epayco-renew-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
  end

  test "early renewal preserves remaining days" do
    existing = PaymentEngine::Membership.create!(
      owner: @owner,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current - 27.days,
      expires_at: Time.current + 3.days,
      source: "purchase"
    )

    purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: @monthly, amount: 14_900, currency: "COP", status: "pending")
    payment = PaymentEngine::Payment.create!(purchase: purchase, amount: purchase.amount, currency: "COP", status: "pending", provider_code: "epayco")
    purchase.update!(payment: payment)

    post "/payment_engine/webhooks/epayco", params: webhook_payload(purchase, "1", "Aceptada")

    assert_response :ok
    assert_in_range (existing.expires_at + 1.month).to_i, (purchase.reload.membership.reload.expires_at.to_i - 1)..(purchase.reload.membership.expires_at.to_i + 1)
  end

  test "early renewal with 15 remaining days preserves time" do
    existing = create_membership(expires_at: Time.current + 15.days)
    purchase = create_purchase

    post "/payment_engine/webhooks/epayco", params: webhook_payload(purchase, "1", "Aceptada")

    assert_response :ok
    assert_in_range (existing.expires_at + 1.month).to_i, expires_range(purchase)
  end

  test "renewal exactly on expiration date starts a new period" do
    create_membership(expires_at: Time.current)
    purchase = create_purchase

    post "/payment_engine/webhooks/epayco", params: webhook_payload(purchase, "1", "Aceptada")

    assert_response :ok
    assert_in_range (purchase.created_at + 1.month).to_i, expires_range(purchase)
  end

  test "annual early renewal preserves remaining time" do
    existing = create_membership(expires_at: Time.current + 3.days)
    purchase = create_purchase(option: @annual, amount: 149_900)

    post "/payment_engine/webhooks/epayco", params: webhook_payload(purchase, "1", "Aceptada", "149900.00")

    assert_response :ok
    assert_in_range (existing.expires_at + 12.months).to_i, expires_range(purchase)
  end

  test "renewal after expiration starts from payment date" do
    expired = PaymentEngine::Membership.create!(
      owner: @owner,
      membership_type: @membership_type,
      status: "expired",
      starts_at: 2.months.ago,
      expires_at: 1.month.ago,
      source: "purchase"
    )

    purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: @monthly, amount: 14_900, currency: "COP", status: "pending")
    payment = PaymentEngine::Payment.create!(purchase: purchase, amount: purchase.amount, currency: "COP", status: "pending", provider_code: "epayco")
    purchase.update!(payment: payment)

    post "/payment_engine/webhooks/epayco", params: webhook_payload(purchase, "1", "Aceptada")

    assert_response :ok
    membership = purchase.reload.membership
    refute_equal expired.id, membership.id
    assert_in_range (purchase.created_at + 1.month).to_i, (membership.expires_at.to_i - 2)..(membership.expires_at.to_i + 2)
  end

  test "failed payment does not extend membership" do
    existing = PaymentEngine::Membership.create!(
      owner: @owner,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current - 27.days,
      expires_at: Time.current + 3.days,
      source: "purchase"
    )

    purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: @monthly, amount: 14_900, currency: "COP", status: "pending")
    payment = PaymentEngine::Payment.create!(purchase: purchase, amount: purchase.amount, currency: "COP", status: "pending", provider_code: "epayco")
    purchase.update!(payment: payment)

    post "/payment_engine/webhooks/epayco", params: webhook_payload(purchase, "2", "Rechazada")

    assert_response :ok
    assert_equal existing.expires_at.to_i, PaymentEngine::Membership.find(existing.id).expires_at.to_i
  end

  test "pending payment does not extend membership" do
    existing = PaymentEngine::Membership.create!(
      owner: @owner,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current - 27.days,
      expires_at: Time.current + 3.days,
      source: "purchase"
    )

    purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: @monthly, amount: 14_900, currency: "COP", status: "pending")
    payment = PaymentEngine::Payment.create!(purchase: purchase, amount: purchase.amount, currency: "COP", status: "pending", provider_code: "epayco")
    purchase.update!(payment: payment)

    post "/payment_engine/webhooks/epayco", params: webhook_payload(purchase, "3", "Pendiente")

    assert_response :ok
    assert_equal existing.expires_at.to_i, PaymentEngine::Membership.find(existing.id).expires_at.to_i
  end

  test "duplicate webhook delivery does not extend twice" do
    existing = PaymentEngine::Membership.create!(
      owner: @owner,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current - 27.days,
      expires_at: Time.current + 3.days,
      source: "purchase"
    )

    purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: @monthly, amount: 14_900, currency: "COP", status: "pending")
    payment = PaymentEngine::Payment.create!(purchase: purchase, amount: purchase.amount, currency: "COP", status: "pending", provider_code: "epayco")
    purchase.update!(payment: payment)

    params = webhook_payload(purchase, "1", "Aceptada")
    post "/payment_engine/webhooks/epayco", params: params
    assert_response :ok
    first_expires = PaymentEngine::Membership.find(existing.id).expires_at.to_i

    post "/payment_engine/webhooks/epayco", params: params
    assert_response :ok
    assert_equal first_expires, PaymentEngine::Membership.find(existing.id).expires_at.to_i
  end

  test "multiple consecutive early renewals preserve time" do
    existing = PaymentEngine::Membership.create!(
      owner: @owner,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current - 27.days,
      expires_at: Time.current + 3.days,
      source: "purchase"
    )

    2.times do
      purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: @monthly, amount: 14_900, currency: "COP", status: "pending")
      payment = PaymentEngine::Payment.create!(purchase: purchase, amount: purchase.amount, currency: "COP", status: "pending", provider_code: "epayco")
      purchase.update!(payment: payment)
      post "/payment_engine/webhooks/epayco", params: webhook_payload(purchase, "1", "Aceptada")
      assert_response :ok
    end

    assert_in_range (existing.expires_at + 2.months).to_i, (PaymentEngine::Membership.find(existing.id).expires_at.to_i - 2)..(PaymentEngine::Membership.find(existing.id).expires_at.to_i + 2)
  end

  test "verification preserves remaining time and does not extend twice" do
    existing = PaymentEngine::Membership.create!(
      owner: @owner,
      membership_type: @membership_type,
      status: "active",
      starts_at: Time.current - 27.days,
      expires_at: Time.current + 3.days,
      source: "purchase"
    )

    purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: @monthly, amount: 14_900, currency: "COP", status: "pending")

    result = PaymentEngine::Payments::Verify.call(provider: "fake", reference: "ref-verify", purchase: purchase)
    assert result.success?
    assert_equal "succeeded", result.data[:state]

    expected = (existing.expires_at + 1.month).to_i
    first_expires = purchase.reload.membership.expires_at.to_i
    assert_in_range expected, (first_expires - 2)..(first_expires + 2)

    again = PaymentEngine::Payments::Verify.call(provider: "fake", reference: "ref-verify", purchase: purchase.reload)
    assert again.success?
    assert_equal first_expires, purchase.reload.membership.expires_at.to_i
  end

  private

  def create_membership(expires_at:, status: "active")
    PaymentEngine::Membership.create!(
      owner: @owner,
      membership_type: @membership_type,
      status: status,
      starts_at: Time.current - 27.days,
      expires_at: expires_at,
      source: "purchase"
    )
  end

  def create_purchase(option: @monthly, amount: 14_900)
    purchase = PaymentEngine::Purchase.create!(owner: @owner, payment_option: option, amount: amount, currency: "COP", status: "pending")
    payment = PaymentEngine::Payment.create!(purchase: purchase, amount: purchase.amount, currency: "COP", status: "pending", provider_code: "epayco")
    purchase.update!(payment: payment)
    purchase
  end

  def expires_range(purchase)
    expires = purchase.reload.membership.expires_at.to_i
    (expires - 2)..(expires + 2)
  end

  def webhook_payload(purchase, code, response, amount = "14900.00")
    signature = Digest::SHA256.hexdigest(
      [ @customer_id, @p_key, "ref-#{purchase.id}", "txn-#{purchase.id}", amount, "COP" ].join("^")
    )
    {
      "x_ref_payco" => "ref-#{purchase.id}",
      "x_transaction_id" => "txn-#{purchase.id}",
      "x_amount" => amount,
      "x_currency_code" => "COP",
      "x_id_factura" => purchase.id,
      "x_signature" => signature,
      "x_cod_response" => code,
      "x_response" => response,
      "x_transaction_date" => Time.current.strftime("%Y-%m-%d %H:%M:%S")
    }
  end

  def assert_in_range(expected, range)
    assert range.include?(expected), "expected #{expected} to be within #{range.inspect}"
  end
end