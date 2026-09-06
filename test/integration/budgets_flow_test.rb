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
    Expense.create!(user: @user, category: category, amount: amount, date: date, description: "Test expense")
  end

  test "index renders budget cards with amounts, progress and on-track status" do
    budget = Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    create_expense(@restaurants, 620_000)

    get budgets_path(month: "2026-09")

    assert_response :success
    assert_select "h1", text: /Presupuestos/
    assert_select ".card", text: /Restaurants/
    assert_select "a[href=?]", edit_budget_path(budget)
    assert_select ".progress[aria-valuenow='78']"
    assert_select ".progress-bar.bg-success"
    assert_select "div.small.text-muted", text: "Gastado"
    assert_select "span.badge.bg-success", text: /En camino/
  end

  test "index shows remaining amount for an on-track budget" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 800_000)
    create_expense(@restaurants, 620_000)

    get budgets_path(month: "2026-09")

    assert_select ".card", text: /Disponible/
    assert_select ".fw-bold.text-success", text: "$180.000"
  end

  test "index shows exceeded amount and over-budget status" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 500_000)
    create_expense(@restaurants, 620_000)

    get budgets_path(month: "2026-09")

    assert_select ".card", text: /Excedido/
    assert_select ".fw-bold.text-danger", text: "$120.000"
    assert_select ".progress-bar.bg-danger"
    assert_select "span.badge.bg-danger", text: /Superado/
  end

  test "index shows near-limit status at 80% usage" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    create_expense(@restaurants, 80_000)

    get budgets_path(month: "2026-09")

    assert_select ".progress-bar.bg-warning"
    assert_select "span.badge.bg-warning", text: /Cerca del límite/
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

  test "index supports navigating to previous months" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    create_expense(@restaurants, 40_000, @month)
    create_expense(@restaurants, 90_000, @month.prev_month)

    get budgets_path(month: @month.prev_month.strftime("%Y-%m"))

    assert_response :success
    assert_select "h5", text: /Agosto/
    assert_select ".progress[aria-valuenow='90']"
    assert_select "a[href='#{budgets_path}']", text: /Volver al mes actual/
  end

  test "index shows the current month pill and no empty state CTA when budgets exist" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)

    get budgets_path

    assert_select "span.badge", text: /Presupuesto del mes actual/
    assert_select ".card", text: /Aún no tienes presupuestos/, count: 0
  end

  test "index shows an empty state with a create CTA when no budgets exist" do
    get budgets_path

    assert_response :success
    assert_select "h4", text: "Aún no tienes presupuestos"
    assert_select "a[href=?]", new_budget_path
  end

  test "dashboard shows the budgets summary card when budgets exist" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)
    create_expense(@restaurants, 80_000)

    get "/dashboard"

    assert_response :success
    assert_select ".card", text: /Presupuestos/
    assert_select "a[href=?]", budgets_path, text: /Ver todos/
    assert_select ".progress-bar.bg-warning"
  end

  test "dashboard does not show the budgets card when no budgets exist" do
    get "/dashboard"

    assert_response :success
    assert_select "a[href=?]", budgets_path, text: /Ver todos/, count: 0
  end

  test "budgets navigation appears in the sidebar" do
    Budget.create!(user: @user, category: @restaurants, monthly_amount: 100_000)

    get budgets_path

    assert_response :success
    assert_select ".sidebar-link[href=?]", budgets_path, text: /Presupuestos/
  end
end
