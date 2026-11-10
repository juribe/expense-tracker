# frozen_string_literal: true

require "application_system_test_case"

# The opportunity banner sits outside the tab list, so its call to action must
# explicitly open the simulator tab instead of relying on Bootstrap's
# data-bs-toggle handling (which requires a tab-list ancestor).
class CreditsOpportunityTabTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Créditos UI", email: "credits_opportunity_ui@example.com",
                         password: "password123")
    @user.confirm
    @loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    @loan.create_credit_account!(
      outstanding_balance: 10_000_000, interest_rate: 2.0, interest_rate_type: "monthly",
      installment_amount: 1_000_000, installment_count: 18, installments_paid: 0,
      start_date: Date.current.prev_month
    )
  end

  test "the opportunity button opens the simulator tab" do
    sign_in @user
    visit money_source_credits_path(@loan)

    assert_button "Simular pago extraordinario"
    click_button "Simular pago extraordinario"

    assert_selector "#credit-tab-simulador", visible: true
    assert_selector "#credit-tab-simulador-btn.active"
    assert_selector "#credit-tab-resumen", visible: false
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "Correo electrónico", with: user.email, match: :first
    fill_in "Contraseña", with: "password123", match: :first
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end
