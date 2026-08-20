require "application_system_test_case"

class QaValidateDashboardReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardReportsTest < ApplicationSystemTestCase
  test "user can view dashboard and generate reports" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"
    assert_text "Welcome, test@example.com"

    # Verify dashboard content
    assert_text "Your Expenses"
    assert_selector ".expense-list"

    # Create a new expense
    click_link "New Expense"
    assert_current_path "/expenses/new"
    fill_in "Amount", with: "50.00"
    fill_in "Description", with: "Lunch"
    select "Food", from: "Category"
    click_button "Create Expense"
    assert_text "Expense was successfully created."

    # Navigate to reports
    click_link "Reports"
    assert_current_path "/reports"
    assert_text "Monthly Report"

    # Generate report for January 2024
    select "January 2024", from: "Month"
    click_button "Generate"
    assert_text "Total Expenses: $50.00"
  end
end
end
