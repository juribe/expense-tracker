# frozen_string_literal: true

require "application_system_test_case"

# El modal de "Pagar" de gastos mensuales debe rellenar el monto con el valor
# de la plantilla formateado en es-CO ("120.000"), no con una cantidad inflada
# por el formateador de miles ("12.000.000"), y al confirmar debe crear una
# transacción con el monto real.
class MonthlyExpensesProcessModalTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless
  include ActionView::Helpers::NumberHelper

  setup do
    @user = User.create!(name: "Monthly Pay User", email: "monthly_pay@example.com", password: "password123")
    @user.confirm
    @services = Category.create!(user: @user, name: "Servicios", category_type: "expense", is_default: false)
    @account = MoneySource.create!(user: @user, name: "Davibank", kind: "account", starting_balance: 1_000_000)
    @template = create_template("Internet hogar", 120_000)
  end

  test "pay modal shows the template amount without inflation" do
    sign_in @user
    visit monthly_expenses_path

    open_process_modal(@template)

    assert_equal "120.000", find("#processAmount").value
    assert_equal "-$120.000", find("#processConfiguredAmount").text
  end

  test "confirming the payment creates the transaction with the real amount" do
    sign_in @user
    visit monthly_expenses_path

    open_process_modal(@template)
    find('[data-testid="confirm-process"]').click

    assert_text I18n.t("recurring.processed_on", action: @template.completed_action_label,
                                                 amount: number_to_currency(-120_000),
                                                 date: I18n.l(Date.current, format: :long))
    transaction = @template.transactions.first
    assert transaction
    assert_equal -120_000.0, transaction.amount.to_f
  end

  private

  def create_template(description, amount)
    @user.recurring_templates.create!(
      category: @services, kind: "expense", description: description,
      amount: amount, frequency: "monthly", source: "manual", payment_day: 10,
      money_source: @account
    )
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end

  def open_process_modal(template)
    within "tr[data-testid='recurring-row'][data-id='#{template.id}']" do
      find('[data-testid="process"]').click
    end
    assert_selector "#processModal.show", wait: 5
  end
end
