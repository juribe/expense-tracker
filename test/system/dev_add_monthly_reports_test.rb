require "application_system_test_case"

class DevAddMonthlyReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class MonthlyReportsTest < ApplicationSystemTestCase
  test "user can add monthly report" do
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "Signed in successfully."
    assert_current_path "/"

    visit "/monthly_reports/new"
    fill_in "Month", with: "January"
    fill_in "Year", with: "2024"
    fill_in "Total expenses", with: "1234.56"
    fill_in "Description", with: "January expenses"
    # If there is a category select:
    # select "Rent", from: "Category"
    click_button "Create Report"
    assert_text "Monthly Report was successfully created."
    assert_current_path "/monthly_reports/1"
  end
end
end
