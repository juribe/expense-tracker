# frozen_string_literal: true

require "test_helper"

class DashboardMoneyTrackingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "simple mode hides account metrics, sources and advanced navigation" do
    user = simple_user
    sign_in user

    get dashboard_path

    assert_response :success
    assert_select "[data-testid=dashboard-page]"
    assert_select "[data-testid=dashboard-kpi-accounts]", count: 0
    assert_select "a", text: "Efectivo y Cuentas", count: 0
    assert_select "a", text: "Tarjetas de Crédito", count: 0
    assert_select "a", text: "Transferencias", count: 0
    assert_select "a", text: "Día de Balance", count: 0
    assert_select "a", text: "Seguimiento de dinero"
  end

  test "advanced mode keeps account metrics and advanced navigation" do
    user = detailed_user
    sign_in user

    get dashboard_path

    assert_response :success
    assert_select "[data-testid=dashboard-kpi-accounts]"
    assert_select "a", text: "Efectivo y Cuentas"
    assert_select "a", text: "Tarjetas de Crédito"
    assert_select "a", text: "Transferencias"
    assert_select "a", text: "Día de Balance"
    assert_select "a", text: "Seguimiento de dinero"
  end

  test "simple mode hides money source filters from the reports" do
    user = simple_user
    sign_in user

    get reports_transactions_path

    assert_response :success
    assert_select "select[name='money_source_id']", count: 0
  end

  test "advanced mode keeps money source filters in the reports" do
    user = detailed_user
    sign_in user

    get reports_transactions_path

    assert_response :success
    assert_select "select[name='money_source_id']"
  end

  test "simple mode redirects advanced money management routes to the dashboard" do
    user = simple_user
    sign_in user

    [ money_sources_cash_path, transfers_path, reconciliation_path,
      reports_money_sources_path, reports_credit_cards_path, reports_loans_path ].each do |path|
      get path
      assert_redirected_to dashboard_path, "expected #{path} to redirect in simple mode"
    end
  end

  test "advanced mode keeps the money sources report available" do
    user = detailed_user
    sign_in user

    get reports_money_sources_path

    assert_response :success
  end

  test "a user without a selected tracking mode is sent to the tracking choice before the dashboard" do
    user = simple_user
    user.update_columns(money_tracking_mode_selected_at: nil)
    sign_in user

    get dashboard_path

    assert_redirected_to money_tracking_path
  end

  test "simple mode does not offer the account setup step in the dashboard onboarding" do
    user = simple_user
    sign_in user

    get dashboard_path

    assert_response :success
    assert_select "[data-testid=onboarding-card-initial]", count: 0
  end

  private

  def simple_user
    user = User.create!(name: "Simple Dashboard", email: "simple_dashboard_#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    user.ensure_general_money_source!
    user
  end

  def detailed_user
    User.create!(name: "Advanced Dashboard", email: "advanced_dashboard_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end
