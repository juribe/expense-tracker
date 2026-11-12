require "test_helper"

# Normalizes a stored raw payload into a payment.rejected event.
class AdminReplayProvider < PaymentEngine::Providers::Base
  def parse_webhook(payload:, headers: {}, raw_body: nil)
    PaymentEngine::Result.success(
      data: { event_type: "payment.rejected", purchase_id: payload["purchase_id"] }
    )
  end
end
PaymentEngine.register_provider(:admin_replay_test, AdminReplayProvider)

class PaymentEngineAdminTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup do
    @user = User.create!(email: "user@example.com", password: "password123", password_confirmation: "password123", confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
    @admin = User.create!(email: "admin@example.com", password: "password123", password_confirmation: "password123", admin: true, confirmed_at: Time.current, financial_cycle_start_day: 1, debt_capacity_target_percentage: 50, debt_capacity_alert_percentage: 80)
  end

  test "unauthenticated redirected to login" do
    get "/payment_engine/admin"
    assert_response :redirect
  end

  test "normal user redirected to the dashboard" do
    sign_in @user
    get "/payment_engine/admin"

    assert_redirected_to "/dashboard"
    assert_equal I18n.t("errors.not_authorized"), flash[:alert]
  end

  test "normal user redirected from a nested admin route" do
    sign_in @user
    get "/payment_engine/admin/payment_options"

    assert_redirected_to "/dashboard"
    assert_equal I18n.t("errors.not_authorized"), flash[:alert]
  end

  test "admin can access dashboard" do
    sign_in @admin
    get "/payment_engine/admin"
    assert_response :success
  end

  test "admin can access all admin routes" do
    sign_in @admin
    [ "/payment_engine/admin/membership_types", "/payment_engine/admin/payment_options", "/payment_engine/admin/memberships", "/payment_engine/admin/subscriptions", "/payment_engine/admin/purchases", "/payment_engine/admin/payments", "/payment_engine/admin/providers", "/payment_engine/admin/webhook_events", "/payment_engine/admin/settings", "/payment_engine/admin/premium_identities" ].each do |path|
      get path
      assert_response :success, "Failed for #{path}"
    end
  end

  test "membership update is audited" do
    sign_in @admin
    membership = create_membership

    patch "/payment_engine/admin/memberships/#{membership.id}", params: { membership: { status: "suspended" } }

    assert_redirected_to "/payment_engine/admin/memberships/#{membership.id}"
    assert_equal "suspended", membership.reload.status
    audit = PaymentEngine::AuditLog.where(action: "membership.updated").last
    assert audit
    assert_equal @admin.id.to_s, audit.actor_id
    assert_equal membership.id.to_s, audit.auditable_id
  end

  test "settings update is audited" do
    sign_in @admin

    patch "/payment_engine/admin/settings", params: { setting: { default_currency: "USD" } }

    assert_redirected_to "/payment_engine/admin/settings"
    audit = PaymentEngine::AuditLog.where(action: "settings.updated").last
    assert audit
    assert_equal @admin.id.to_s, audit.actor_id
  end

  test "provider create, update and destroy are audited" do
    sign_in @admin

    post "/payment_engine/admin/providers", params: { provider: { code: "audit_provider", name: "Audit Provider", environment: "sandbox" } }
    provider = PaymentEngine::Provider.find_by!(code: "audit_provider")
    patch "/payment_engine/admin/providers/#{provider.id}", params: { provider: { name: "Audit Provider 2" } }
    delete "/payment_engine/admin/providers/#{provider.id}"

    actions = PaymentEngine::AuditLog.where(action: %w[provider.created provider.updated provider.destroyed]).order(:id).pluck(:action)
    assert_equal %w[provider.created provider.updated provider.destroyed], actions
    assert PaymentEngine::AuditLog.where(action: "provider.updated").last.actor_id == @admin.id.to_s
  end

  test "reprocess applies the stored payload through the provider adapter" do
    sign_in @admin
    purchase = PaymentEngine::Purchase.create!(owner: @user, amount: 1_000, currency: "COP", status: "pending")
    event = PaymentEngine::WebhookEvent.create!(
      provider_code: "admin_replay_test",
      external_id: "evt-replay",
      status: "failed",
      payload: { "purchase_id" => purchase.id },
      received_at: Time.current
    )

    post "/payment_engine/admin/webhook_events/#{event.id}/reprocess"

    assert_redirected_to "/payment_engine/admin/webhook_events/#{event.id}"
    assert_equal "processed", event.reload.status
    assert_equal "failed", purchase.reload.status
  end

  test "reprocess keeps the event failed when the provider cannot be resolved" do
    sign_in @admin
    event = PaymentEngine::WebhookEvent.create!(
      provider_code: "missing_provider",
      external_id: "evt-missing",
      status: "failed",
      payload: { "event_type" => "payment.rejected" },
      received_at: Time.current
    )

    post "/payment_engine/admin/webhook_events/#{event.id}/reprocess"

    assert_redirected_to "/payment_engine/admin/webhook_events/#{event.id}"
    assert_equal "failed", event.reload.status
    assert_match(/no se pudo/i, flash[:alert].to_s)
  end

  test "normal user cannot access premium identities" do
    sign_in @user

    get "/payment_engine/admin/premium_identities"

    assert_redirected_to "/dashboard"
  end

  test "admin can release a premium identity with an audit entry" do
    identity = PremiumIdentities::Protection.claim!(
      identity_type: "account_email",
      value: "admin-release@example.com",
      user: @user
    )
    sign_in @admin

    get "/payment_engine/admin/premium_identities/#{identity.id}"
    assert_response :success

    post "/payment_engine/admin/premium_identities/#{identity.id}/release",
         params: { reason: "Verified support request" }

    assert_redirected_to "/payment_engine/admin/premium_identities/#{identity.id}"
    assert identity.reload.released?
    audit = PaymentEngine::AuditLog.where(action: "premium_identity.released").last
    assert audit
    assert_equal @admin.id.to_s, audit.actor_id
    assert_equal "Verified support request", audit.reason
  end

  private

  def create_membership
    membership_type = PaymentEngine::MembershipType.create!(code: "ADMIN_AUDIT", name: "Admin Audit", status: "active")
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: membership_type,
      status: "active",
      starts_at: Time.current,
      expires_at: 1.month.from_now
    )
  end
end
