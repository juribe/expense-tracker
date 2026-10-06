# frozen_string_literal: true

require "application_system_test_case"

class ReconciliationAssignModalTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(name: "Cuadre Modal User", email: "cuadre_modal@example.com", password: "password123")
    @category = Category.create!(user: @user, name: "Servicios")
    @template = RecurringTemplate.create!(
      user: @user, category: @category, kind: "expense",
      description: "Crédito carro", amount: 2_818_000, frequency: "monthly",
      source: "manual", payment_day: 5
    )
    MoneySource.create!(user: @user, name: "Davibank", kind: "account", starting_balance: 8_400_000)
  end

  test "assign modal reopens after being closed" do
    sign_in @user
    visit reconciliation_path

    find("button.js-assign-payment").click
    assert_selector "#assignPaymentModal.show"
    find("#assignPaymentModal .btn-close").click
    assert_no_selector "#assignPaymentModal.show" # wait for the hide transition

    find("button.js-assign-payment").click
    assert_selector "#assignPaymentModal.show"
  end

  test "assign modal works across a failed-then-successful assign cycle" do
    # Simulates the stuck state: an expense linked to the template but dated
    # outside the cuadre period, so the row stays pending.
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro pasado", amount: 2_818_000,
      kind: "expense", source: "gmail", date: 1.month.ago.to_date
    )
    Expenses::RecurringAssignment.assign(user: @user, expense_id: expense.id, recurring_template_id: @template.id)

    sign_in @user
    visit reconciliation_path
    assert_selector "button.js-assign-payment" # row still pending

    # Out-of-period expense no longer appears: search is scoped to the period.
    find("button.js-assign-payment").click
    assert_selector "#assignPaymentModal.show"
    fill_in "assignExpenseSearch", with: "crédito"
    assert_no_selector "#assignExpenseResults .js-assign-result", wait: 3
    find("#assignPaymentModal .btn-close").click

    # Retry opens the modal again.
    find("button.js-assign-payment").click
    assert_selector "#assignPaymentModal.show"
    find("#assignPaymentModal .btn-close").click

    # Assigning a valid in-period expense clears the row after the reload,
    # and the modal keeps working on the fresh page.
    in_period = @user.expenses.create!(
      category: @category, description: "Pago crédito carro octubre", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current
    )
    visit reconciliation_path
    find("button.js-assign-payment").click
    fill_in "assignExpenseSearch", with: "octubre"
    find("#assignExpenseResults .js-assign-result").click
    click_button I18n.t("reconciliation.assign.submit", default: "Asignar pago")

    assert_text I18n.t("reconciliation.flashes.assigned", description: @template.description), wait: 5
    refute_selector "button.js-assign-payment", wait: 5 # pending row gone after reload

    assert_equal 0, ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m")).pending_payments_count
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
