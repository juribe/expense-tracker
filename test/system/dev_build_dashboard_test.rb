require "application_system_test_case"

class DevBuildDashboardTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardTest < ApplicationSystemTestCase
  test "user can sign up, create expense, and view dashboard" do
    # Sign up
    visit "/users/sign_up"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123"
    click_button "Sign up"
    assert_text "Welcome! You have signed up successfully."
    assert_current_path "/"

    # Navigate to dashboard
    click_link "Dashboard"
    assert_current_path "/dashboard"
    assert_text "Your Expenses"
    assert_selector "h1", text: "Dashboard"

    # Add a new expense
    click_link "Add Expense"
    assert_current_path "/expenses/new"
    fill_in "Amount", with: "45.67"
    fill_in "Description", with: "Lunch at cafe"
    select "Food", from: "Category"
    fill_in "Date", with: "2023-09-15"
    click_button "Create Expense"
    assert_text "Expense was successfully created."
    assert_current_path "/expenses"

    # Verify expense appears on dashboard
    visit "/dashboard"
    assert_current_path "/dashboard"
    assert_text "Lunch at cafe"
    assert_text "$45.67"
    assert_selector ".expense-row", text: "Lunch at cafe"

    # Filter expenses by date range
    select "This month", from: "Date Range"
    click_button "Filter"
    assert_text "Showing expenses for This month"
    assert_selector ".expense-row", text: "Lunch at cafe"
  end
end
end
