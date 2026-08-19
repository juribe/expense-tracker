require "application_system_test_case"

class QaValidateDashboardReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardReportsTest < ApplicationSystemTestCase
  test "user can view dashboard and generate expense report" do
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Sign in"
    assert_text "Welcome back!"
    assert_current_path "/dashboard"

    click_link "Reports"
    assert_current_path "/reports"

    click_link "New Expense"
    assert_current_path "/expenses/new"

    fill_in "Amount", with: "50.00"
    fill_in "Category", with: "Travel"
    fill_in "Date", with: "2023-03-15"
    fill_in "Description", with: "Taxi to airport"
    click_button "Create Expense"
    assert_text "Expense was successfully created."
    assert_current_path "/expenses"

    click_link "Reports"
    assert_current_path "/reports"

    select "Monthly", from: "Report Type"
    click_button "Generate Report"
    assert_text "Report generated for March 2023"
    assert_selector "table#report-table"
    assert_current_path "/reports/monthly?month=2023-03"
  end
end
end
