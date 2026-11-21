# frozen_string_literal: true

require "application_system_test_case"

# Día de Balance: loans open a dedicated modal that mirrors the loan-interest
# mockup, while every other money source keeps the shared reconcile modal.
class ReconciliationReconcileModalTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Cuadre Loan Modal", email: "cuadre_loan_modal@example.com",
                         password: "password123")
    @user.confirm
    @account = MoneySource.create!(user: @user, name: "Davibank Ahorros", kind: "account",
                                   starting_balance: 8_400_000)
    @loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    @loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)
  end

  test "loans use the dedicated modal and accounts keep the shared modal" do
    sign_in @user
    visit reconciliation_path

    open_loan_reconcile_modal

    assert_selector "#reconcileLoanModal .rec-loan-summary"
    assert_selector "#reconcileLoanModal .rec-loan-notice"
    assert_selector "#reconcileLoanModal .rec-loan-entry-grid"
    assert_selector "#reconcileLoanModal .rec-loan-footer"
    assert_no_selector "#reconcileCreateExpense"
    assert_no_selector "#reconcileCreateIncome"

    find("#reconcileLoanModal .btn-close").click
    assert_no_selector "#reconcileLoanModal.show", wait: 5

    scroll_and_click(find("li.list-group-item", text: @account.name).find("button.js-reconcile", text: "Verificar saldo"))
    assert_selector "#reconcileModal.show"
    assert_no_selector "#reconcileLoanModal.show"
    assert_selector "#reconcileCreateExpense", visible: true
    assert_selector "#reconcileCreateIncome", visible: true
    assert_no_selector "#reconcileModal .rec-loan-summary"
    assert_no_selector "#reconcileModal .rec-loan-notice"
    assert_text "Saldo real"
  end

  test "loan with interest calculation shows principal, estimated interest and estimated total" do
    enable_loan_interest(@loan)
    sign_in @user
    visit reconciliation_path

    open_loan_reconcile_modal

    assert_selector "#reconcileLoanModal [data-testid='loan-interest-breakdown']", visible: true
    assert_selector "#reconcileLoanModal .rec-loan-card", count: 2
    assert_selector "#reconcileLoanModal .rec-loan-breakdown", visible: true
    assert_selector "#reconcileLoanModal .rec-loan-amount", text: "$32.000.000"
    assert_selector "#reconcileLoanModal [data-testid='loan-interest-warning']", visible: true
    assert_selector "#reconcileLoanModal .rec-loan-entry-grid"
    assert_selector "#reconcileLoanModal .rec-loan-footer .rec-loan-btn-ok"
    assert_selector "#reconcileLoanModal .rec-loan-footer .rec-loan-btn-primary"

    assert_text "Capital pendiente en Yogasto"
    assert_text "Capital pendiente según el banco"
    assert_text "Intereses causados (estimados)"
    assert_text "Deuda total estimada"
    assert_text "Diferencia frente al capital de Yogasto"
    assert_no_text "Este cuadre modifica el capital pendiente."
  end

  test "loan reconciliation difference compares principal only" do
    enable_loan_interest(@loan)
    sign_in @user
    visit reconciliation_path

    open_loan_reconcile_modal

    estimate = @loan.reload.estimated_accrued_interest
    assert_operator estimate, :>, 0

    fill_in "loanReconcileActualBalance", with: (32_000_000 + estimate.round).to_s

    expected = ActiveSupport::NumberHelper.number_to_delimited(estimate.round)
    assert_includes find("#reconcileLoanModal .js-difference").text, expected
  end

  test "loan without interest calculation does not show an estimated interest" do
    @loan.credit_account.update!(interest_calculation_enabled: false)
    sign_in @user
    visit reconciliation_path

    open_loan_reconcile_modal

    assert_selector "#reconcileLoanModal .rec-loan-summary.is-single"
    assert_selector "#reconcileLoanModal .rec-loan-amount", text: "$32.000.000"
    assert_no_selector "#reconcileLoanModal .rec-loan-breakdown", visible: true
    assert_no_text "Intereses causados (estimados)"
    assert_selector "#reconcileLoanModal [data-testid='loan-interest-warning']", visible: true
    assert_text "Capital pendiente según el banco"
  end

  test "saving a loan reconciliation records only the entered principal" do
    enable_loan_interest(@loan)
    sign_in @user
    visit reconciliation_path

    open_loan_reconcile_modal

    estimate = @loan.reload.estimated_accrued_interest
    assert_operator estimate, :>, 0

    fill_in "loanReconcileActualBalance", with: "31.000.000"
    fill_in "loanReconcileNote", with: "Cuadre banco"
    click_button "Guardar nuevo saldo"

    assert_text "Saldo registrado."
    assert_selector "[data-testid='debt-row']", text: @loan.name

    outstanding = @loan.credit_account.reload.outstanding_balance
    assert_equal 31_000_000.to_d, outstanding
    refute_equal 31_000_000.to_d + estimate, outstanding
  end

  test "loan modal opens at the top without focusing the principal input" do
    enable_loan_interest(@loan)
    sign_in @user
    visit reconciliation_path

    open_loan_reconcile_modal

    assert_selector "#reconcileLoanModal .rec-loan-summary", visible: true
    assert_equal 0, page.evaluate_script("document.querySelector('#reconcileLoanModal .modal-body').scrollTop")
    assert_not_equal "loanReconcileActualBalance",
                     page.evaluate_script("document.activeElement && document.activeElement.id")
  end

  test "the loan movements action opens the dedicated loan modal at the top" do
    sign_in @user
    visit reconciliation_path

    scroll_and_click(find("li.list-group-item", text: @loan.name).find("button.js-reconcile", text: "Movimientos"))
    assert_selector "#reconcileLoanModal.show"
    assert_selector "#reconcileLoanModal .rec-loan-summary", visible: true
    assert_equal 0, page.evaluate_script("document.querySelector('#reconcileLoanModal .modal-body').scrollTop")
  end

  private

  def open_loan_reconcile_modal
    page.execute_script("var banner=document.querySelector('[data-pwa-install-banner]'); if (banner) banner.remove();")
    scroll_and_click(find("li.list-group-item", text: @loan.name).find("button.js-reconcile", text: "Verificar deuda"))
    assert_selector "#reconcileLoanModal.show"
    wait_for_modal_transition "#reconcileLoanModal"
  end

  def enable_loan_interest(loan)
    loan.credit_account.update!(
      interest_rate: 18.05,
      interest_rate_type: "effective_annual",
      interest_calculation_enabled: true,
      interest_calculation_day: 11,
      start_date: 1.year.ago.to_date,
      payment_frequency: "monthly"
    )
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in", default: "Iniciar sesión")
    assert_selector "aside.left-sidebar", wait: 10
  end
end
