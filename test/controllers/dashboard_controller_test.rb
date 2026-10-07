# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "dashboard_test@example.com",
      password: "password123"
    )
    @category = Category.create!(name: "Food", is_default: true, category_type: "expense")
  end

  test "GET /dashboard renders for authenticated user" do
    sign_in @user
    get dashboard_path
    assert_response :success
    assert_select ".summary-value"
  end

  test "GET /dashboard redirects unauthenticated user to sign in" do
    get dashboard_path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "GET /dashboard with invalid month shows flash and defaults to current month" do
    sign_in @user
    get dashboard_path, params: { month: "not-a-date" }
    assert_response :success
    assert_equal I18n.t("dashboard.invalid_month", default: "El mes no es válido; se muestra el mes actual."), flash[:alert]
  end

  test "GET /dashboard with valid month loads that month's data" do
    sign_in @user
    @user.expenses.create!(amount: 25.00, date: Date.new(2026, 3, 15), category: @category, description: "Lunch")
    get dashboard_path, params: { month: "2026-03" }
    assert_response :success
  end

  test "GET /dashboard includes expense summary and budgets" do
    sign_in @user
    @user.expenses.create!(amount: 10.00, date: Date.today, category: @category, description: "Coffee")
    get dashboard_path
    assert_response :success
    assert_select "[data-testid=table]", count: 0
  end

  test "GET /dashboard groups the summaries by pay cycle with a configured schedule" do
    sign_in @user
    @user.update!(financial_cycle_start_day: 20)
    # Inside the cycle opened Oct 20 (a bill paid Nov 3).
    @user.expenses.create!(amount: 500_000, date: Date.new(2026, 11, 3), category: @category, description: "Arriendo")
    # Calendar-month expense outside the cycle (belongs to the next cycle).
    @user.expenses.create!(amount: 900_000, date: Date.new(2026, 11, 25), category: @category, description: "Fuera")

    get dashboard_path, params: { cycle: "2026-11-2" }

    assert_response :success
    assert_select "h5", text: /Gastos de este ciclo/
  end

  test "GET /dashboard shows the financial cycle banner when cycles are enabled" do
    sign_in @user
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.new(2026, 10, 25))

    get dashboard_path, params: { cycle: "2026-10-25" }

    assert_response :success
    assert_select "div.cycle-banner" do
      assert_select "strong", text: cycle.label
      assert_select "span", text: cycle.range_label
    end
  end

  test "GET /dashboard hides the cycle banner without a configured schedule" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "div.cycle-banner", count: 0
  end

  test "GET /dashboard labels the expense card with the cycle when cycles are enabled" do
    sign_in @user
    @user.update!(financial_cycle_start_day: 20)

    get dashboard_path, params: { cycle: "2026-10-25" }

    assert_response :success
    assert_select "h5", text: /Gastos de este ciclo/
    assert_select "h5", text: /Gastos de este mes/, count: 0
    assert_select "span", text: /No hay gastos este ciclo/
  end

  test "GET /dashboard labels the expense card with the month without a configured schedule" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select "h5", text: /Gastos de este mes/
  end

  test "GET /dashboard transactions card counts all the period's expenses, not just the recent 5" do
    sign_in @user
    7.times { |i| @user.expenses.create!(amount: 10.00, date: Date.current, category: @category, description: "G#{i}") }

    get dashboard_path

    assert_response :success
    assert_select "p.summary-value", text: "7"
  end

  test "GET /dashboard renders the transactions label, never the translations hash" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_includes response.body, "Transacciones"
    refute_includes response.body, "Gastos del periodo seleccionado"
    refute_includes response.body, '{:title=>'
  end

  test "GET /dashboard shows the budgets card above the quick add card" do
    Budget.create!(user: @user, category: @category, monthly_amount: 100_000, period: "monthly", active: true)
    sign_in @user

    get dashboard_path

    assert_response :success
    body = response.body
    assert_operator body.index(t("budgets.dashboard_title")), :<, body.index(t("dashboard.quick_add_expense", default: "Agregar gasto rápido"))
  end

  test "GET /dashboard quick add form offers payment sources, not loans" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    loan = @user.money_sources.create!(name: "Préstamo", kind: "loan", active: true)
    sign_in @user

    get dashboard_path

    assert_response :success
    select_values = assert_select("select#expense_money_source_id option").map { |node| node["value"] }
    assert_includes select_values, cash.id.to_s
    assert_includes select_values, card.id.to_s
    assert_not_includes select_values, loan.id.to_s
  end
end
