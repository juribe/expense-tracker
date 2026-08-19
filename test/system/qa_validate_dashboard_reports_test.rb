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
    assert_text "Dashboard"
    assert_current_path "/dashboard"

    # Verify dashboard widgets are present
    assert_selector "h2", text: "Monthly Expenses"
    assert_selector ".total-expense", text: "$0.00"

    # Create a sample expense to have data for reports
    click_link "Add Expense"
    fill_in "Amount", with: "120.50"
    fill_in "Description", with: "Office Supplies"
    select "2023", from: "Year"
    select "March", from: "Month"
    select "Supplies", from: "Category"
    click_button "Create Expense"
    assert_text "Expense was successfully created"
    assert_current_path "/expenses"

    # Return to dashboard and verify the new expense appears
    click_link "Dashboard"
    assert_current_path "/dashboard"
    assert_text "Office Supplies"
    assert_selector ".total-expense", text: "$120.50"

    # Navigate to reports page
    click_link "Reports"
    assert_current_path "/reports"
    assert_text "Generate Report"

    # Generate a monthly report
    select "March 2023", from: "Month"
    select "All Categories", from: "Category"
    click_button "Generate"
    assert_text "Report for March 2023"
    assert_selector "table.report-table"
    assert_text "Office Supplies"
    assert_text "$120.50"

    # Verify download link for the report
    assert_selector "a", text: "Download CSV"
    click_link "Download CSV"
    # Assuming the download triggers a response, we just confirm the link exists
    assert_text "Your CSV report is being prepared"
  end
end
end
