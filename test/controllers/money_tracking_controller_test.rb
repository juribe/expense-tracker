# frozen_string_literal: true

require "test_helper"

class MoneyTrackingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = create_user(email: "money_tracking_ctrl@example.com")
    sign_in @user
  end

  test "GET /settings/money_tracking shows the onboarding choice when the mode is not selected" do
    @user.update_columns(money_tracking_mode: "simple", money_tracking_mode_selected_at: nil)

    get money_tracking_path

    assert_response :success
    assert_select "[data-testid=money-tracking-onboarding]"
    assert_select "h1", text: "¿Cómo quieres controlar tu dinero?"
    assert_select "input[type=radio][name='money_tracking_mode'][value=simple][checked]"
    assert_select "input[type=radio][name='money_tracking_mode'][value=detailed]:not([checked])"
    assert_select "[data-testid=money-tracking-option-simple]", text: /Quiero controlar mis gastos/
    assert_select "[data-testid=money-tracking-option-detailed]", text: /Quiero administrar todas mis cuentas/
    assert_select "body", text: /Puedes cambiar esta opción cuando quieras/
    refute_includes response.body, "Money Source"
  end

  test "PATCH /settings/money_tracking saves the simple mode and enters the dashboard" do
    @user.update_columns(money_tracking_mode: "simple", money_tracking_mode_selected_at: nil)

    patch money_tracking_path, params: { money_tracking_mode: "simple" }

    assert_redirected_to dashboard_path
    @user.reload
    assert_equal "simple", @user.money_tracking_mode
    assert @user.money_tracking_mode_selected_at.present?
  end

  test "PATCH /settings/money_tracking with advanced converts General into an account" do
    @user.update_columns(money_tracking_mode: "simple", money_tracking_mode_selected_at: nil)
    general = MoneySources::General.ensure_for(@user)
    general_id = general.id

    patch money_tracking_path, params: { money_tracking_mode: "detailed" }

    assert_redirected_to dashboard_path
    @user.reload
    assert_equal "detailed", @user.money_tracking_mode
    assert_equal general_id, @user.general_money_source.id
    assert_equal "account", @user.general_money_source.kind
  end

  test "GET /settings/money_tracking shows the current mode after onboarding" do
    @user.update_columns(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)

    get money_tracking_path

    assert_response :success
    assert_select "[data-testid=money-tracking-settings]"
    assert_select "[data-testid=money-tracking-current-mode]", text: /Avanzado/
    assert_select "h1", text: "Seguimiento de dinero"
  end

  test "changing from advanced to simple asks for confirmation first" do
    @user.update_columns(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)
    general = MoneySources::General.ensure_for(@user)
    MoneySources::ModeSwitch.new(user: @user, mode: "detailed").call
    assert_equal "account", general.reload.kind

    patch money_tracking_path, params: { money_tracking_mode: "simple" }

    assert_response :success
    assert_select "[data-testid=money-tracking-confirm]"
    assert_select "body", text: /Los movimientos no serán eliminados/
    assert_select "body", text: /Las fuentes individuales permanecerán almacenadas/
    @user.reload
    assert_equal "detailed", @user.money_tracking_mode
    assert_equal "account", general.reload.kind
  end

  test "confirmed change from advanced to simple hides the advanced features" do
    @user.update_columns(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)
    general = MoneySources::General.ensure_for(@user)
    MoneySources::ModeSwitch.new(user: @user, mode: "detailed").call

    patch money_tracking_path, params: { money_tracking_mode: "simple", confirmed: "1" }

    assert_redirected_to money_tracking_path
    @user.reload
    assert_equal "simple", @user.money_tracking_mode
    assert_equal "general", general.reload.kind
  end

  test "advanced settings allow choosing the default money source" do
    @user.update_columns(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)
    account = @user.money_sources.create!(name: "Cuenta principal", kind: "account", starting_balance: 100_000)
    sign_in @user

    patch money_tracking_default_source_path, params: { default_money_source_id: account.id }

    assert_redirected_to money_tracking_path
    assert_equal account.id, @user.reload.default_money_source_id
  end

  test "advanced settings reject a default source of another user" do
    @user.update_columns(money_tracking_mode: "detailed", money_tracking_mode_selected_at: Time.current)
    other = User.create!(name: "Other", email: "money_tracking_other@example.com", password: "password123")
    foreign = other.money_sources.create!(name: "Ajena", kind: "account")

    patch money_tracking_default_source_path, params: { default_money_source_id: foreign.id }

    assert_redirected_to money_tracking_path
    assert_nil @user.reload.default_money_source_id
  end

  test "simple settings do not offer a default money source" do
    @user.update_columns(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)

    get money_tracking_path

    assert_response :success
    assert_select "[data-testid=money-tracking-default-source]", count: 0
  end

  test "changing the tracking mode does not touch the membership" do
    membership_type = PaymentEngine::MembershipType.create!(
      name: "Tracking Mode Membership",
      code: "TRACKING_MODE_#{SecureRandom.hex(6)}",
      status: "active"
    )
    membership = PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.month.ago,
      expires_at: 1.month.from_now
    )
    before = membership.attributes.slice("status", "source", "starts_at", "expires_at", "membership_type_id")

    patch money_tracking_path, params: { money_tracking_mode: "simple", confirmed: "1" }

    assert_redirected_to money_tracking_path
    assert_equal before, membership.reload.attributes.slice("status", "source", "starts_at", "expires_at",
                                                            "membership_type_id")
  end

  private

  def create_user(email:)
    User.create!(name: "Money Tracking User", email: email, password: "password123")
  end
end
