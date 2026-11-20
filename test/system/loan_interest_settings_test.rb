# frozen_string_literal: true

require "application_system_test_case"

class LoanInterestSettingsSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(
      name: "Loan Interest System",
      email: "loan_interest_system_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @user.confirm
    institution = FinancialInstitution.create!(
      canonical_name: "DAVIbank debug #{SecureRandom.hex(3)}",
      slug: "davibank-debug-#{SecureRandom.hex(3)}",
      institution_type: "bank"
    )
    @loan = @user.money_sources.create!(
      name: "Crédito Hipotecario en Pesos", kind: "loan", sub_kind: "mortgage",
      active: true, identifier: "2442", institution: institution
    )
    @loan.create_credit_account!(
      principal_amount: 170_900_000,
      outstanding_balance: 67_166_819.12,
      interest_rate: 18.05,
      interest_rate_type: "effective_annual",
      installment_amount: 1_130_575,
      installment_count: 192,
      installments_paid: 41,
      start_date: Date.new(2023, 6, 13)
    )
  end

  test "saving the loan form persists the monthly interest settings" do
    sign_in @user
    visit edit_money_source_path(@loan)
    page.execute_script("document.querySelectorAll('[data-pwa-install-banner], [data-pwa-update]').forEach(function (el) { el.hidden = true; })")

    assert_no_selector ".loan-interest-panel"

    check "money_source_credit_account_attributes_interest_calculation_enabled"
    assert_selector ".loan-interest-panel"
    fill_in "Día de referencia mensual", with: "11"
    click_button "Guardar préstamo"

    assert_current_path money_sources_loans_path
    account = @loan.reload.credit_account
    assert account.interest_calculation_enabled?, "expected interest calculation to be enabled"
    assert_equal 11, account.interest_calculation_day

    visit edit_money_source_path(@loan)
    assert_checked_field "money_source_credit_account_attributes_interest_calculation_enabled"
    assert_selector ".loan-interest-panel"
    assert_field "Día de referencia mensual", with: "11"
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end
end
