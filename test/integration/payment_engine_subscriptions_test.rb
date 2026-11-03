require "test_helper"

# Keeps the monthly pricing flow simple: no recurring subscription is created
# in PaymentEngine while the ePayco subscription module is not used yet.
class PaymentEngineSubscriptionsTest < ActiveSupport::TestCase
  setup do
    @membership_type = PaymentEngine::MembershipType.find_or_create_by!(code: "BASIC") { |m| m.name = "Membresía Básica"; m.status = "active" }
    @monthly = PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @membership_type, name: "Mensual") do |po|
      po.price = 14_900
      po.currency = "COP"
      po.mode = "recurring"
      po.interval = "month"
      po.interval_count = 1
      po.access_duration_count = 1
      po.access_duration_unit = "month"
      po.status = "active"
    end
    @user = User.create!(email: "epayco-sub-#{SecureRandom.hex(4)}@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
  end

  test "monthly card payment does not create a subscription" do
    purchase = PaymentEngine::Purchase.create!(owner: @user, payment_option: @monthly, amount: @monthly.price, currency: "COP", status: "pending")
    payment = PaymentEngine::Payment.create!(purchase: purchase, amount: @monthly.price, currency: "COP", status: "pending", provider_code: "epayco", payment_method: "card")
    purchase.update!(payment: payment)

    result = PaymentEngine::Webhooks::Process.call(
      webhook_event: webhook_event,
      data: approved_data(purchase)
    )

    assert result.success?
    assert_equal "succeeded", payment.reload.status
    assert_equal "paid", purchase.reload.status
    assert_nil PaymentEngine::Subscription.find_by(owner: @user, payment_option: @monthly)
  end

  test "monthly PSE payment does not create a subscription" do
    purchase = PaymentEngine::Purchase.create!(owner: @user, payment_option: @monthly, amount: @monthly.price, currency: "COP", status: "pending")
    payment = PaymentEngine::Payment.create!(purchase: purchase, amount: @monthly.price, currency: "COP", status: "pending", provider_code: "epayco", payment_method: "pse")
    purchase.update!(payment: payment)

    result = PaymentEngine::Webhooks::Process.call(
      webhook_event: webhook_event,
      data: approved_data(purchase)
    )

    assert result.success?
    assert_nil PaymentEngine::Subscription.find_by(owner: @user, payment_option: @monthly)
  end

  private

  def webhook_event
    PaymentEngine::WebhookEvent.find_or_create_by!(provider_code: "epayco", external_id: "evt-#{Time.current.to_i}") do |e|
      e.event_type = "payment.approved"
      e.status = "received"
      e.received_at = Time.current
    end
  end

  def approved_data(purchase)
    {
      event_type: "payment.approved",
      purchase_id: purchase.id,
      amount: purchase.amount.to_i,
      currency: purchase.currency,
      provider_transaction_id: "txn-#{purchase.id}"
    }.stringify_keys
  end
end
