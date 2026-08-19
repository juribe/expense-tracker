require "application_system_test_case"

class QaValidateDashboardReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardAndReportsTest < ApplicationSystemTestCase
  test "user can view dashboard and generate expense report" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"
    assert_text "Welcome, test@example.com"

    # Verify dashboard widgets
    assert_selector "h2", text: "Recent Expenses"
    assert_selector "div.dashboard-summary"
    assert_selector "span.total-expense", text: /\$\d+/

    # Navigate to Reports page
    click_link "Reports"
    assert_current_path "/reports"
    assert_text "Generate Expense Report"

    # Set report filters
    select "Last 30 Days", from: "Date Range"
    select "All Categories", from: "Category"
    click_button "Generate Report"

    # Verify report output
    assert_text "Expense Report"
    assert_selector "table.report-table"
    assert_selector "th", text: "Date"
    assert_selector "th", text: "Category"
    assert_selector "th", text: "Amount"
    assert_text "$"

    # Export the report
    click_button "Export CSV"
    assert_text "Report exported successfully"
  end
end
end
