# frozen_string_literal: true

require "application_system_test_case"

# Día de Balance UI: source-scoped movements, pagination, category filtering
# in the assign modal, and the debt-specific modal labels.
class ReconciliationUiTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Reconciliation UI User", email: "reconciliation_ui@example.com",
                         password: "password123")
    @user.confirm
    @category = Category.create!(user: @user, name: "Servicios")
    @other_category = Category.create!(user: @user, name: "Transporte")
    @account = MoneySource.create!(user: @user, name: "Davibank Ahorros", kind: "account",
                                   starting_balance: 8_400_000)
    @other_account = MoneySource.create!(user: @user, name: "Otra cuenta", kind: "account",
                                         starting_balance: 1_000_000)
    @template = RecurringTemplate.create!(
      user: @user, category: @category, kind: "expense", description: "Internet",
      amount: 180_000, frequency: "monthly", source: "manual", payment_day: 7
    )
  end

  test "assign modal filters by category and no longer offers Gmail sync" do
    matching = @user.expenses.create!(
      category: @category, description: "Pago Internet", amount: 180_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @account
    )
    @user.expenses.create!(
      category: @other_category, description: "Pago Internet transporte", amount: 180_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @account
    )
    sign_in @user
    visit reconciliation_path

    scroll_and_click(find("button.js-assign-payment"))
    assert_selector "#assignPaymentModal.show"
    assert_no_text "Sync Gmail"
    assert_text @category.name

    fill_in "assignExpenseSearch", with: "Pago Internet"
    assert_selector "#assignExpenseResults .js-assign-result", count: 1
    assert_selector "#assignExpenseResults .js-assign-result", text: matching.description
    assert_link "Abrir"
  end

  test "movements modal is scoped to the source and loads more with pagination" do
    9.times do |index|
      @user.expenses.create!(
        category: @category, description: "Movimiento #{index}", amount: 10_000 + index,
        kind: "expense", source: "manual", date: Date.current, money_source: @account
      )
    end
    @user.expenses.create!(
      category: @category, description: "Movimiento ajeno", amount: 50_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @other_account
    )
    sign_in @user
    visit reconciliation_path

    row = find("[data-testid='account-row']", text: @account.name)
    scroll_and_click(row.find("button", text: "Movimientos"))
    assert_selector "#reconcileModal.show"
    assert_text "Movimiento 8"
    assert_no_text "Movimiento ajeno"
    assert_selector "#reconcileSearchResults .rec-movement-item", count: 8

    click_button "Cargar más movimientos"
    assert_selector "#reconcileSearchResults .rec-movement-item", count: 9
  end

  test "debt modal uses the debt label and hides loan create links" do
    loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)
    sign_in @user
    visit reconciliation_path

    scroll_and_click(find("[data-testid='debt-row']", text: loan.name).find("button", text: "Verificar saldo"))
    assert_selector "#reconcileModal.show"
    assert_text "Deuda en #{AppName.current}"
    assert_no_selector "#reconcileCreateExpense", visible: true
    assert_no_selector "#reconcileCreateIncome", visible: true
  end

  private

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in", default: "Iniciar sesión")
    assert_selector "aside.left-sidebar", wait: 10
  end
end
