require "application_system_test_case"

class DevBuildDashboardTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardSystemTest < Capybara::SystemTestCase
  test "user can view dashboard summary" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Login"
    assert_current_path "/dashboard"
    assert_text "Financial Overview"
    assert_selector ".total-balance"
    assert_selector ".recent-transactions"
  end
  test "user can see expense breakdown by category" do
    visit "/dashboard"
    assert_text "Monthly Spending"
    assert_selector "#expense-chart"
    assert_text "Food"
    assert_text "Rent"
    assert_text "Entertainment"
  end
  test "user can see recent transactions list" do
    visit "/dashboard"
    within ".recent-transactions" do
      assert_text "Grocery Store"
      assert_text "$50.00"
      assert_text "Subscription Service"
      assert_text "$15.99"
    end
  end
  test "user can navigate to add new expense" do
    visit "/dashboard"
    click_link "Add Expense"
    assert_current_path "/expenses/new"
    assert_selector "form"
  end
end
end
