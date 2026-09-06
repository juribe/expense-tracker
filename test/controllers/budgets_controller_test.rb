# frozen_string_literal: true

require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "budgets_controller_test@example.com",
      password: "password123"
    )
    @category = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    sign_in @user
  end

  test "GET /budgets renders the index" do
    budget = Budget.create!(user: @user, category: @category, monthly_amount: 800_000)
    get budgets_path
    assert_response :success
    assert_select "h1", text: /Presupuestos/
    assert_select "a[href=?]", new_budget_path
    assert_select "a[href=?]", edit_budget_path(budget)
  end

  test "GET /budgets accepts a month param" do
    get budgets_path(month: "2026-09")
    assert_response :success
    assert_select "h5", text: /Septiembre/
  end

  test "GET /budgets with an invalid month falls back to the current month" do
    get budgets_path(month: "not-a-month")
    assert_response :success
    assert_match I18n.t("budgets.invalid_month"), flash[:alert]
  end

  test "GET /budgets/new renders the form with expense categories" do
    income_category = Category.create!(name: "Salary", is_default: true, category_type: "income")
    get new_budget_path
    assert_response :success
    assert_select "form"
    assert_select "#budget_category_id"
    assert_select "option[value=?]", @category.id.to_s
    assert_select "option[value=?]", income_category.id.to_s, count: 0
  end

  test "POST /budgets creates a budget for the current user" do
    assert_difference("Budget.count", 1) do
      post budgets_path, params: { budget: { category_id: @category.id, monthly_amount: "800000" } }
    end
    budget = Budget.last
    assert_equal @user, budget.user
    assert_equal @category, budget.category
    assert_equal 800_000, budget.monthly_amount
    assert_equal "monthly", budget.period
    assert budget.active?
    assert_redirected_to budgets_path
    assert_equal I18n.t("budgets.flashes.created"), flash[:notice]
  end

  test "POST /budgets with invalid params re-renders the form" do
    assert_no_difference("Budget.count") do
      post budgets_path, params: { budget: { category_id: nil, monthly_amount: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "div.invalid-feedback"
  end

  test "POST /budgets rejects an income category" do
    income_category = Category.create!(name: "Salary", is_default: true, category_type: "income")
    assert_no_difference("Budget.count") do
      post budgets_path, params: { budget: { category_id: income_category.id, monthly_amount: "100000" } }
    end
    assert_response :unprocessable_entity
  end

  test "GET /budgets/:id/edit renders the form for the current user's budget" do
    budget = Budget.create!(user: @user, category: @category, monthly_amount: 800_000)
    get edit_budget_path(budget)
    assert_response :success
    assert_select "form"
  end

  test "PATCH /budgets/:id updates the budget" do
    budget = Budget.create!(user: @user, category: @category, monthly_amount: 800_000)
    patch budget_path(budget), params: { budget: { monthly_amount: "950000" } }
    assert_equal 950_000, budget.reload.monthly_amount
    assert_redirected_to budgets_path
    assert_equal I18n.t("budgets.flashes.updated"), flash[:notice]
  end

  test "PATCH /budgets/:id with invalid params re-renders the form" do
    budget = Budget.create!(user: @user, category: @category, monthly_amount: 800_000)
    assert_no_difference("Budget.count") do
      patch budget_path(budget), params: { budget: { monthly_amount: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "DELETE /budgets/:id destroys the budget" do
    budget = Budget.create!(user: @user, category: @category, monthly_amount: 800_000)
    assert_difference("Budget.count", -1) do
      delete budget_path(budget)
    end
    assert_redirected_to budgets_path
    assert_equal I18n.t("budgets.flashes.destroyed"), flash[:notice]
  end

  test "cannot edit another user's budget" do
    other_user = User.create!(name: "Other", email: "budgets_other_user@example.com", password: "password123")
    other_budget = Budget.create!(user: other_user, category: @category, monthly_amount: 100_000)
    get edit_budget_path(other_budget)
    assert_redirected_to budgets_path
    assert_equal I18n.t("budgets.not_found"), flash[:alert]
  end

  test "cannot destroy another user's budget" do
    other_user = User.create!(name: "Other", email: "budgets_other_destroy@example.com", password: "password123")
    other_budget = Budget.create!(user: other_user, category: @category, monthly_amount: 100_000)
    assert_no_difference("Budget.count") do
      delete budget_path(other_budget)
    end
    assert_redirected_to budgets_path
    assert_equal I18n.t("budgets.not_found"), flash[:alert]
  end
end
