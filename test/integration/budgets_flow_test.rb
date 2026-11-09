# frozen_string_literal: true

require "test_helper"

class BudgetsFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "budgets_flow@example.com",
      password: "password123"
    )
    @restaurants = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    @shopping = Category.create!(name: "Shopping", is_default: true, category_type: "expense")
    @month = Date.new(2026, 9, 1)
    sign_in @user
  end

  def create_expense(category, amount, date = @month)
    Expense.create!(user: @user, category: category, amount: amount, date: date, description: "Test expense",
                    money_source: @money_source || (@money_source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 10_000_000)))
  end

  def budget_card_names
    css_select(".budget-card .budget-category-name").map { |node| node.text.strip }
  end

  test "index renders budget cards with amounts, progress and the attention state" do
    budget = Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    create_expense(@restaurants, 620_000)

    get budgets_path(month: "2026-09")

    assert_response :success
    assert_select "h1", text: /Presupuestos/
    assert_select ".budget-card", text: /Restaurants/
    assert_select "a[href=?]", edit_budget_path(budget)
    assert_select ".progress[aria-valuenow='78']"
    assert_select ".budget-card.budget-card--attention"
    assert_select "[data-testid=budget-spent-amount]", text: "$620.000"
    assert_select "[data-testid=budget-status]", text: /Atención/
  end

  test "index shows the available amount for a budget below its limit" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    create_expense(@restaurants, 620_000)

    get budgets_path(month: "2026-09")

    assert_select "[data-testid=budget-available-amount]", text: "$180.000"
    assert_select "[data-testid=budget-budget-amount]", text: "$800.000"
  end

  test "index shows a negative available amount and exceeded hint for an over-budget card" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 500_000)
    create_expense(@restaurants, 620_000)

    get budgets_path(month: "2026-09")

    assert_select ".budget-card.budget-card--over-budget"
    assert_select "[data-testid=budget-available-amount]", text: "-$120.000"
    assert_select "[data-testid=budget-exceeded-hint]", text: "Superado por $120.000"
    assert_select "[data-testid=budget-status]", text: /Presupuesto superado/
  end

  test "index shows a zero-spend budget with the full amount available" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)

    get budgets_path(month: "2026-09")

    assert_select "[data-testid=budget-spent-amount]", text: "$0"
    assert_select "[data-testid=budget-available-amount]", text: "$100.000"
    assert_select ".progress[aria-valuenow='0']"
    assert_select "[data-testid=budget-status]", text: /En camino/
  end

  test "index shows the attention state from 75 percent usage" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    create_expense(@restaurants, 75_000)

    get budgets_path(month: "2026-09")

    assert_select ".budget-card.budget-card--attention"
    assert_select "[data-testid=budget-status]", text: /Atención/
  end

  test "index shows the near-limit state from 90 percent usage" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    create_expense(@restaurants, 90_000)

    get budgets_path(month: "2026-09")

    assert_select ".budget-card.budget-card--near-limit"
    assert_select "[data-testid=budget-status]", text: /Cerca del límite/
  end

  test "index shows the over-budget state at 100 percent usage" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    create_expense(@restaurants, 100_000)

    get budgets_path(month: "2026-09")

    assert_select ".budget-card.budget-card--over-budget"
    assert_select "[data-testid=budget-available-amount]", text: "$0"
    assert_select "[data-testid=budget-status]", text: /Presupuesto superado/
    assert_select "[data-testid=budget-exhausted-hint]", text: "Sin dinero disponible"
  end

  test "index renders period summary metrics from the selected period data" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    Budget.create!(user: @user, category: @shopping, monthly_amount: 200_000)
    create_expense(@restaurants, 50_000)
    create_expense(@shopping, 190_000)

    get budgets_path(month: "2026-09")

    assert_select "[data-testid=budget-summary-total]", text: "$300.000"
    assert_select "[data-testid=budget-summary-spent]", text: "$240.000"
    assert_select "[data-testid=budget-summary-available]", text: "$60.000"
    assert_select "[data-testid=budget-summary-risk]", text: "1"
    assert_select ".budget-toolbar-subtitle", text: /2 presupuestos · 1 cerca del límite · 0 superados/
  end

  test "index sorts budgets by usage percentage" do
    entertainment = Category.create!(name: "Entertainment", is_default: true, category_type: "expense")
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    Budget.create!(user: @user, category: @shopping, monthly_amount: 200_000)
    Budget.create!(user: @user, category: entertainment, monthly_amount: 50_000)
    create_expense(@restaurants, 20_000)
    create_expense(@shopping, 100_000)
    create_expense(entertainment, 60_000)

    get budgets_path(month: "2026-09", sort: "usage")

    assert_equal [ "Entertainment", "Shopping", "Restaurants" ], budget_card_names
  end

  test "index sorts budgets by lowest available amount" do
    entertainment = Category.create!(name: "Entertainment", is_default: true, category_type: "expense")
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    Budget.create!(user: @user, category: @shopping, monthly_amount: 200_000)
    Budget.create!(user: @user, category: entertainment, monthly_amount: 50_000)
    create_expense(@restaurants, 20_000)
    create_expense(@shopping, 100_000)
    create_expense(entertainment, 60_000)

    get budgets_path(month: "2026-09", sort: "available")

    assert_equal [ "Entertainment", "Restaurants", "Shopping" ], budget_card_names
  end

  test "index sorts budgets by highest budget amount" do
    entertainment = Category.create!(name: "Entertainment", is_default: true, category_type: "expense")
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    Budget.create!(user: @user, category: @shopping, monthly_amount: 200_000)
    Budget.create!(user: @user, category: entertainment, monthly_amount: 50_000)

    get budgets_path(month: "2026-09", sort: "budget")

    assert_equal [ "Shopping", "Restaurants", "Entertainment" ], budget_card_names
  end

  test "index sorts budgets by highest spending" do
    entertainment = Category.create!(name: "Entertainment", is_default: true, category_type: "expense")
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    Budget.create!(user: @user, category: @shopping, monthly_amount: 200_000)
    Budget.create!(user: @user, category: entertainment, monthly_amount: 50_000)
    create_expense(@restaurants, 20_000)
    create_expense(@shopping, 100_000)
    create_expense(entertainment, 60_000)

    get budgets_path(month: "2026-09", sort: "spent")

    assert_equal [ "Shopping", "Entertainment", "Restaurants" ], budget_card_names
  end

  test "each budget links to its category analysis for the selected month" do
    budget = Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)

    get budgets_path(month: "2026-09")

    link = css_select("a[data-testid=budget-analysis]").first
    refute_nil link
    uri = URI.parse(link["href"])
    params = Rack::Utils.parse_query(uri.query)

    assert_equal reports_budgets_path, uri.path
    assert_equal budget.category_id.to_s, params["category_id"]
    assert_equal "custom", params["period"]
    assert_equal "2026-09-01", params["start_date"]
    assert_equal "2026-09-30", params["end_date"]
  end

  test "each budget links to its category analysis for the selected financial cycle" do
    @user.update!(financial_cycle_start_day: 20)
    budget = Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)

    get budgets_path(cycle: "2026-10-20")

    link = css_select("a[data-testid=budget-analysis]").first
    uri = URI.parse(link["href"])
    params = Rack::Utils.parse_query(uri.query)

    assert_equal reports_budgets_path, uri.path
    assert_equal budget.category_id.to_s, params["category_id"]
    assert_equal "2026-10-20", params["start_date"]
    assert_equal "2026-11-19", params["end_date"]
  end

  test "the budget analysis link target renders the filtered report" do
    budget = Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)

    get reports_budgets_path(
      category_id: budget.category_id,
      period: "custom",
      start_date: "2026-09-01",
      end_date: "2026-09-30"
    )

    assert_response :success
    assert_select "[data-testid=budget-report]"
  end

  test "spent calculation excludes transfers on the index page" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    create_expense(@restaurants, 40_000)

    savings = @user.money_sources.create!(name: "Savings", kind: "account", starting_balance: 100_000)
    checking = @user.money_sources.create!(name: "Checking", kind: "account", starting_balance: 0)
    Transfer.create!(user: @user, from_source: savings, to_source: checking, amount: 30_000, date: @month)

    get budgets_path(month: "2026-09")

    assert_select ".progress[aria-valuenow='40']"
  end

  test "index shows the selected month in the period badge without navigation controls" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    create_expense(@restaurants, 40_000, @month)
    create_expense(@restaurants, 90_000, @month.prev_month)

    get budgets_path(month: @month.prev_month.strftime("%Y-%m"))

    assert_response :success
    assert_select "[data-testid=cycle-badge]", text: /Agosto/
    assert_select ".progress[aria-valuenow='90']"
    assert_select ".budget-period-arrow", count: 0
    assert_select "a[href='#{budgets_path}']", text: /Volver al mes actual/, count: 0
  end

  test "index shows the current period badge and no empty state CTA when budgets exist" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)

    get budgets_path

    assert_select "[data-testid=cycle-badge]", text: /#{I18n.l(Date.current, format: :month_year)}/
    assert_select ".budget-card", text: /Aún no tienes presupuestos/, count: 0
  end

  test "index shows a month navigation and an empty state with a create CTA when no budgets exist" do
    get budgets_path(month: "2026-09")

    assert_response :success
    assert_select "[data-testid=cycle-badge]", text: /Septiembre/
    assert_select "[data-testid=budgets-empty]", text: /Aún no tienes presupuestos/
    assert_select "[data-testid=budgets-summary]", count: 0
    assert_select "a[href=?]", new_budget_path
  end

  test "dashboard shows the budgets summary card when budgets exist" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    # The dashboard budgets card is always scoped to the current month, so the
    # 80% usage must be created there (a fixed September date breaks on Oct 1+).
    create_expense(@restaurants, 80_000, Date.current)

    get "/dashboard"

    assert_response :success
    assert_select "[data-testid=dashboard-budget]", text: /Presupuesto del ciclo/
    assert_select "a[href=?]", budgets_path(month: Date.current.strftime("%Y-%m")), text: /Ver presupuesto/
    assert_select ".dash-budget-bar--warning"
  end

  test "dashboard does not show the budgets card when no budgets exist" do
    get "/dashboard"

    assert_response :success
    assert_select "[data-testid=dashboard-budget]", count: 0
  end

  test "budgets navigation appears in the sidebar" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)

    get budgets_path

    assert_response :success
    assert_select ".sidebar-link[href=?]", budgets_path, text: /Presupuestos/
  end
end
