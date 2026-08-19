require "application_system_test_case"

class DevAddMonthlyReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class MonthlyReportsTest < ApplicationSystemTestCase
  test "user can add a monthly report" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "Signed in successfully"
    assert_current_path "/"

    # Navigate to Monthly Reports page
    click_link "Monthly Reports"
    assert_current_path "/monthly_reports"
    assert_text "Monthly Reports"

    # Go to new report form
    click_link "New Report"
    assert_current_path "/monthly_reports/new"
    assert_text "New Monthly Report"

    # Fill in the report form
    select "March", from: "Month"
    select "2024", from: "Year"
    fill_in "Total Expenses", with: "1234.56"
    fill_in "Notes", with: "Business travel and office supplies"
    click_button "Create Report"

    # Verify report creation
    assert_current_path "/monthly_reports"
    assert_text "Report was successfully created"
    assert_selector "tr", text: "March 2024"
    assert_selector "td", text: "$1,234.56"
    assert_text "Business travel and office supplies"
  end
end
end
