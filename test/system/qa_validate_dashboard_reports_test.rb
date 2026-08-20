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
    assert_text "Welcome, test@example.com"
    assert_selector "h1", text: "Dashboard"
    assert_text "Total Expenses"
    assert_text "$0.00"
    assert_selector ".expense-summary"
  end

  test "user can navigate to reports page from dashboard" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"

    click_link "Reports"
    assert_current_path "/reports"
    assert_selector "h1", text: "Reports"
    assert_text "Generate a new expense report"
  end

  test "user can generate expense report with filters" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"

    click_link "Reports"
    assert_current_path "/reports"

    fill_in "Start date", with: "2023-01-01"
    fill_in "End date", with: "2023-12-31"
    select "Monthly", from: "Frequency"
    click_button "Generate Report"

    assert_text "Expense Report"
    assert_selector "table.report"
    assert_text "Total"
    assert_text "$0.00"
  end

  test "user can export generated report as CSV" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"

    click_link "Reports"
    fill_in "Start date", with: "2023-01-01"
    fill_in "End date", with: "2023-01-31"
    click_button "Generate Report"

    click_button "Export CSV"
    assert_text "Your CSV file is being prepared"
  end

  test "dashboard navigation links work correctly" do
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"

    click_link "Add Expense"
    assert_current_path "/expenses/new"
    assert_selector "h1", text: "New Expense"

    click_link "Dashboard"
    assert_current_path "/dashboard"
    assert_selector "h1", text: "Dashboard"
  end
end
end
