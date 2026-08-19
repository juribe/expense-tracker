require "application_system_test_case"

class QaValidateDashboardReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardAndReportsTest < ApplicationSystemTestCase
  test "user can view dashboard summary" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"
    assert_text "Dashboard"
    assert_text "Total Expenses"
    assert_selector ".expense-summary"
    assert_text "$0.00" # assuming no expenses yet
  end

  test "user can generate expense report for a date range" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    click_link "Reports"
    assert_current_path "/reports"
    fill_in "Start date", with: "2023-01-01"
    fill_in "End date", with: "2023-12-31"
    select "All", from: "Category"
    click_button "Generate Report"
    assert_text "Expense Report"
    assert_text "2023-01-01 to 2023-12-31"
    assert_selector "table.report-table"
    assert_selector "table.report-table tbody tr", minimum: 1
  end

  test "user can filter reports by category and view results" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    click_link "Reports"
    assert_current_path "/reports"
    fill_in "Start date", with: "2023-01-01"
    fill_in "End date", with: "2023-12-31"
    select "All", from: "Category"
    click_button "Generate Report"
    select "Travel", from: "Category"
    click_button "Filter"
    assert_text "Category: Travel"
    assert_selector "table.report-table tbody tr" do |rows|
      rows.each do |row|
        assert_match /Travel/, row.text
      end
    end
  end

  test "user can export the generated report as CSV" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    click_link "Reports"
    assert_current_path "/reports"
    fill_in "Start date", with: "2023-01-01"
    fill_in "End date", with: "2023-12-31"
    select "All", from: "Category"
    click_button "Generate Report"
    click_button "Export CSV"
    assert_text "Your CSV report is being downloaded"
    # Verify that a download link appears (implementation dependent)
    assert_selector "a", text: "Download CSV"
  end
end
end
