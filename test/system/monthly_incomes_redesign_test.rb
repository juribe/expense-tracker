# frozen_string_literal: true

require "application_system_test_case"

# La página de Ingresos Recurrentes muestra el resumen real del ciclo y
# conserva las acciones de la tabla: Recibir como acción principal, editar
# visible y activar/desactivar/eliminar dentro del menú de tres puntos.
class MonthlyIncomesRedesignTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless
  include ActionView::Helpers::NumberHelper

  setup do
    @user = User.create!(name: "Monthly Income UI", email: "monthly_income_ui@example.com",
                         password: "password123")
    @user.confirm
    @category = Category.create!(user: @user, name: "Salario UI", category_type: "income", is_default: false)
    @account = MoneySource.create!(user: @user, name: "Cuenta Ingresos UI", kind: "account",
                                   starting_balance: 0)
    @pending = create_template("Salario nómina", 2_000_000, payment_day: 10)
    @received = create_template("Freelance UI", 500_000, payment_day: 5)
    @received.transactions.create!(
      user: @user, category: @category, amount: 500_000, date: Date.current,
      kind: "income", source: "recurring_template", money_source: @account
    )
  end

  test "shows the cycle summary and keeps the row actions accessible" do
    sign_in @user
    visit monthly_incomes_path

    assert_selector '[data-testid="monthly-incomes-summary"]'
    within '[data-testid="summary-monthly-expected"]' do
      assert_text number_to_currency(2_500_000)
    end
    within '[data-testid="summary-pending"]' do
      assert_text number_to_currency(2_000_000)
      assert_text "1 ingreso pendiente"
    end
    within '[data-testid="summary-received"]' do
      assert_text number_to_currency(500_000)
      assert_text "1 de 2 ingresos recibidos"
    end
    within '[data-testid="summary-next-income"]' do
      assert_text "Salario nómina"
    end

    within row_for(@pending) do
      assert_selector '[data-testid="process"]'
      assert_selector '[data-testid="edit"]'
      find('[data-testid="row-actions"]').click
      assert_selector '.dropdown-menu.show [data-testid="deactivate"]'
      assert_selector '.dropdown-menu.show [data-testid="delete"]'
    end

    within row_for(@received) do
      assert_no_selector '[data-testid="process"]'
      assert_selector '[data-testid="status"] .badge', text: "Recibido"
    end
  end

  test "receive modal uses the row identity and keeps the existing flow" do
    sign_in @user
    visit monthly_incomes_path

    within row_for(@pending) do
      find('[data-testid="process"]').click
    end
    assert_selector "#processModal.show", wait: 5
    wait_for_modal_transition("#processModal")

    assert_equal "Salario UI", find("#processCategory").text
    assert_equal "Salario nómina", find("#processDescription").text
    assert_equal number_to_currency(2_000_000), find("#processConfiguredAmount").text
  end

  private

  def create_template(description, amount, payment_day:)
    @user.recurring_templates.create!(
      category: @category, kind: "income", description: description,
      amount: amount, frequency: "monthly", source: "manual",
      payment_day: payment_day, money_source: @account
    )
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("auth.sign_in")
    assert_selector "aside.left-sidebar", wait: 10
  end

  def row_for(template)
    "tr[data-testid='recurring-row'][data-id='#{template.id}']"
  end
end
