# frozen_string_literal: true

require "test_helper"

# MonthlyIncomesController sirve la página de Ingresos Recurrentes. Estos tests
# verifican que el rediseño use el resumen real del ciclo y conserve las
# acciones existentes sin duplicar ingresos ya recibidos.
class MonthlyIncomesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PremiumAccessTestHelper

  setup do
    @user = User.create!(
      name: "Monthly Incomes User",
      email: "monthly_incomes_test@example.com",
      password: "password123"
    )
    sign_in @user
    @category = Category.create!(name: "Salario Monthly Income", is_default: false,
                                 category_type: "income", user: @user)
    @account = @user.money_sources.create!(name: "Cuenta Nómina Ingresos", kind: "account")
    @template = @user.recurring_templates.create!(
      category: @category, kind: "income", amount: 2_000_000, frequency: "monthly",
      source: "wizard", description: "Salario", money_source: @account
    )
  end

  test "index renders the real summary for the selected financial cycle" do
    @user.update!(financial_cycle_start_day: 20)
    @template.update!(payment_day: 25)
    @template.transactions.create!(
      user: @user, category: @category, amount: 2_000_000, date: Date.new(2026, 11, 1),
      kind: "income", source: "recurring_template", money_source: @account
    )
    @user.recurring_templates.create!(
      category: @category, kind: "income", amount: 500_000, frequency: "monthly",
      source: "manual", description: "Freelance", payment_day: 5
    )

    get monthly_incomes_path(period: "2026-10-25")

    assert_response :success
    assert_select '[data-testid="summary-monthly-expected"]', text: /2\.500\.000/
    assert_select '[data-testid="summary-pending"]', text: /500\.000/
    assert_select '[data-testid="summary-pending"]', text: /1 ingreso pendiente/
    assert_select '[data-testid="summary-received"]', text: /2\.000\.000/
    assert_select '[data-testid="summary-received"]', text: /1 de 2 ingresos recibidos/
    assert_select '[data-testid="summary-next-income"]', text: /Freelance/
    assert_select '[data-testid="summary-next-income"]', text: /500\.000/
  end

  test "invalid create re-renders the index with the summary strip" do
    assert_no_difference "RecurringTemplate.count" do
      post monthly_incomes_path, params: {
        recurring_template: { category_id: @category.id, amount: "", description: "Sin monto" }
      }
    end

    assert_response :unprocessable_entity
    assert_select '[data-testid="monthly-incomes-summary"]'
    assert_select '[data-testid="summary-monthly-expected"]'
  end

  test "completed income hides the receive action and shows the received status" do
    @template.update!(active: true, payment_day: 10)
    @template.transactions.create!(
      user: @user, category: @category, amount: 2_000_000, date: Date.current,
      kind: "income", source: "recurring_template", money_source: @account
    )

    get monthly_incomes_path

    assert_select 'tr[data-id=?] [data-testid="process"]', @template.id.to_s, count: 0
    assert_select 'tr[data-id=?] td[data-testid="status"] .badge', @template.id.to_s,
                  text: I18n.t("monthly_incomes.received")
  end

  test "pending rows keep receive as primary action and group secondary actions" do
    @template.update!(payment_day: 10)

    get monthly_incomes_path

    assert_select 'tr[data-id=?] [data-testid="process"]', @template.id.to_s, count: 1
    assert_select 'tr[data-id=?] [data-testid="edit"]', @template.id.to_s, count: 1
    assert_select 'tr[data-id=?] [data-testid="row-actions"]', @template.id.to_s, count: 1
    assert_select 'tr[data-id=?] .dropdown-menu [data-testid="deactivate"]', @template.id.to_s, count: 1
    assert_select 'tr[data-id=?] .dropdown-menu [data-testid="delete"]', @template.id.to_s, count: 1
  end

  test "empty state renders zero summary values" do
    @template.destroy

    get monthly_incomes_path

    assert_select '[data-testid="empty-state"]'
    assert_select '[data-testid="summary-monthly-expected"]', text: /\$0/
    assert_select '[data-testid="summary-pending"]', text: /\$0/
    assert_select '[data-testid="summary-received"]', text: /\$0/
    assert_select '[data-testid="summary-next-income"]', text: /Sin ingresos pendientes/
  end

  test "index keeps the existing status filter options" do
    get monthly_incomes_path

    assert_select "select[name='status'] option", count: 3
    assert_select "select[name='status'] option[value='completed']"
    assert_select "select[name='status'] option[value='pending']"
  end

  test "manual income entries in the same category count toward the recurring income" do
    @template.update!(payment_day: 10, amount: 2_000_000)
    @template.transactions.create!(
      user: @user, category: @category, amount: 1_000_000, date: Date.current,
      kind: "income", source: "recurring_template", money_source: @account
    )
    @user.incomes.create!(
      amount: 1_000_000, description: "Segundo pago", date: Date.current,
      category: @category, money_source: @account
    )

    get monthly_incomes_path

    assert_response :success
    assert_select '[data-testid="summary-received"]', text: /2\.000\.000/
    assert_select 'tr[data-id=?] td[data-testid="status"] .badge', @template.id.to_s,
                  text: I18n.t("monthly_incomes.received")
    assert_select 'tr[data-id=?] [data-testid="process"]', @template.id.to_s, count: 0
  end

  test "free users see the import templates action locked" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    revoke_premium(@user)

    get monthly_incomes_path

    assert_response :success
    assert_select "button[data-testid='import-templates-locked'][data-bs-target='#importPremiumModal']" do
      assert_select "i.ti-lock"
      assert_select ".premium-action-badge", text: /PREMIUM/
    end
    assert_select "a[href='#{new_import_path}']", count: 0
    assert_select "#importPremiumModal" do
      assert_select "a[href='#{plans_path}']", text: /Conocer Premium/
    end
  end

  test "premium users keep the import templates link" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    grant_premium(@user)

    get monthly_incomes_path

    assert_response :success
    assert_select "a[href='#{new_import_path}']"
    assert_select "#importPremiumModal", count: 0
    assert_select "[data-testid='import-templates-locked']", count: 0
  end
end
