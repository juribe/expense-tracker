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
    assert_current_path "/"

    # Navigate to new monthly report page
    visit "/monthly_reports/new"
    select "January", from: "Month"
    select "2023", from: "Year"
    fill_in "Total Expenses", with: "500"
    click_button "Create Report"

    # Verify success message and navigation
    assert_text "Monthly report created successfully."
    assert_current_path "/monthly_reports"

    # Verify the new report appears in the list
    visit "/monthly_reports"
    assert_text "January 2023"
    assert_text "$500.00"
  end
end
end
