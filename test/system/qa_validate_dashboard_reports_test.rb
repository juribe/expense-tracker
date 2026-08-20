require "application_system_test_case"

class QaValidateDashboardReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardReportsTest < ApplicationSystemTestCase
  test "user can view dashboard and generate expense reports" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"
    assert_text "Dashboard"
    # Add an expense
    click_link "Add Expense"
    assert_current_path "/expenses/new"
    fill_in "Amount", with: "123.45"
    fill_in "Description", with: "Business lunch"
    select "Food", from: "Category"
    fill_in "Date", with: "2023-09-15"
    click_button "Create Expense"
    assert_text "Expense was successfully created"
    assert_current_path "/expenses"
    # Return to dashboard and verify total
    click_link "Dashboard"
    assert_current_path "/dashboard"
    assert_text "Total Expenses"
    assert_text "$123.45"
    # Navigate to reports page
    click_link "Reports"
    assert_current_path "/reports"
    assert_text "Generate Expense Report"
    # Generate a report for September 2023
    select "September", from: "Month"
    select "2023", from: "Year"
    click_button "Generate Report"
    assert_text "Expense Report for September 2023"
    assert_selector "table.report-table"
    assert_text "Business lunch"
    assert_text "$123.45"
  end
end
end
