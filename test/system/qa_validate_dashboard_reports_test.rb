require "application_system_test_case"

class QaValidateDashboardReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardReportsTest < ApplicationSystemTestCase
  test "user can view dashboard and generate reports" do
    # Log in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"
    assert_text "Welcome to your dashboard"

    # Verify dashboard summary
    assert_selector ".expense-summary"

    # Create a new expense
    click_link "New Expense"
    assert_current_path "/expenses/new"
    fill_in "Amount", with: "50.00"
    fill_in "Description", with: "Office supplies"
    select "Office", from: "Category"
    click_button "Create Expense"
    assert_text "Expense was successfully created."
    assert_current_path "/expenses"

    # Navigate to reports
    click_link "Reports"
    assert_current_path "/reports"
    assert_text "Expense Report"
    assert_selector "table#report-table"

    # Filter report by month
    select "January 2024", from: "Month"
    click_button "Filter"
    assert_text "Total Expenses: $50.00"
  end
end
end
