# frozen_string_literal: true

require "application_system_test_case"

# The Conciliar modal on the Día de Cuadre: the "Crear gasto"/"Crear ingreso"
# shortcuts are meaningful for money positions and cards, but a loan
# difference is resolved by registering the real Payment from the loan page.
class ReconciliationReconcileModalTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Cuadre Loan Modal", email: "cuadre_loan_modal@example.com",
                         password: "password123")
    @account = MoneySource.create!(user: @user, name: "Davibank Ahorros", kind: "account",
                                   starting_balance: 8_400_000)
    @loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    @loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)
  end

  test "reconcile modal hides the create links for loans and keeps them for accounts" do
    sign_in @user
    visit reconciliation_path

    find("li.list-group-item", text: @loan.name).find("button.js-reconcile").click
    assert_selector "#reconcileModal.show"
    assert_no_selector "#reconcileCreateExpense", visible: true
    assert_no_selector "#reconcileCreateIncome", visible: true

    find("#reconcileModal .btn-close").click
    assert_no_selector "#reconcileModal.show" # wait for the hide transition

    find("li.list-group-item", text: @account.name).find("button.js-reconcile").click
    assert_selector "#reconcileModal.show"
    assert_selector "#reconcileCreateExpense", visible: true
    assert_selector "#reconcileCreateIncome", visible: true
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "Email", with: user.email, match: :first
    fill_in "Password", with: "password123", match: :first
    click_button I18n.t("auth.sign_in", default: "Iniciar sesión")
    assert_selector "body"
  end
end
