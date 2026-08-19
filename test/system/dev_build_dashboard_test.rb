require "application_system_test_case"

class DevBuildDashboardTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardTest < ApplicationSystemTestCase
  test "user can sign in, add an expense, and view the dashboard" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"

    # Navigate to new expense form
    click_link "Add Expense"
    assert_current_path "/expenses/new"

    # Fill in expense form
    fill_in "Amount", with: "45.67"
    fill_in "Description", with: "Lunch at cafe"
    select "Food", from: "Category"
    fill_in "Date", with: "2023-09-15"
    click_button "Create Expense"

    # Verify expense creation
    assert_text "Expense was successfully created"
    assert_current_path "/expenses"

    # Return to dashboard
    click_link "Dashboard"
    assert_current_path "/dashboard"

    # Verify dashboard summary shows the new expense
    assert_text "Total Expenses"
    assert_selector ".expense-summary", text: "$45.67"
    assert_text "Lunch at cafe"

    # Filter dashboard by month
    select "September 2023", from: "Month"
    click_button "Filter"
    assert_text "Lunch at cafe"
    assert_text "$45.67"
  end
end
end
