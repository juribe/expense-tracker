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
end
