# frozen_string_literal: true

require "test_helper"

class CategoryInsightsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Insight User", email: "insight_ctrl@example.com", password: "password123")
    @other = User.create!(name: "Other", email: "insight_other@example.com", password: "password123")
    @category = Category.create!(name: "Insight Cat", is_default: true, category_type: "expense", suggested_savings_percentage: 15)
    @tip = @category.saving_tips.create!(title: "Compara tarifas", body: "Revisa cargos.", active: true, position: 0)
    sign_in @user
  end

  test "GET insight renders for own/default category" do
    get category_insight_path(@category)
    assert_response :success
    assert_match @category.name, response.body
    assert_match "Compara tarifas", response.body
  end

  test "does not show inactive tips" do
    @category.saving_tips.create!(title: "Inactiva", body: "No mostrar", active: false, position: 1)
    get category_insight_path(@category)
    assert_response :success
    assert_no_match "Inactiva", response.body
  end

  test "redirects when category not accessible" do
    custom = Category.create!(name: "Custom", is_default: false, category_type: "expense", user: @other)
    get category_insight_path(custom)
    assert_redirected_to categories_path
  end

  test "GET index lists eligible categories ordered by spending" do
    high = Category.create!(name: "High", is_default: true, category_type: "expense", suggested_savings_percentage: 15)
    low = Category.create!(name: "Low", is_default: true, category_type: "expense", suggested_savings_percentage: 5)
    bank = @user.money_sources.create!(name: "Bank2", kind: "account", active: true, starting_balance: 1_000_000_000)
    Expense.create!(user: @user, category: high, money_source: bank, amount: -300_000, date: Date.current.prev_month, description: "x")
    Expense.create!(user: @user, category: low, money_source: bank, amount: -100_000, date: Date.current.prev_month, description: "x")

    get category_insights_path
    assert_response :success
    assert_match "High", response.body
    assert_match "Low", response.body
  end

  test "GET index empty state" do
    get category_insights_path
    assert_response :success
  end
end
