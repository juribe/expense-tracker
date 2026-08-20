require "application_system_test_case"

class DevAddMonthlyReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class MonthlyReportsTest < ApplicationSystemTestCase
  test "user can create a monthly report" do
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

    # Start a new report
    click_link "New Report"
    assert_current_path "/monthly_reports/new"
    assert_text "New Monthly Report"

    # Fill in report details
    fill_in "Report Name", with: "July 2023 Report"
    select "July", from: "Month"
    select "2023", from: "Year"
    fill_in "Total Expenses", with: "1500"
    fill_in "Notes", with: "All expenses for July recorded."

    # Add a sample expense line item
    click_link "Add Expense"
    within all(".expense-fields").last do
      fill_in "Category", with: "Travel"
      fill_in "Amount", with: "300"
      fill_in "Description", with: "Flight to conference"
    end

    # Submit the report
    click_button "Create Report"

    # Verify creation
    assert_text "Report was successfully created"
    assert_current_path "/monthly_reports"
    assert_selector "tr", text: "July 2023 Report"
    assert_selector "tr", text: "$1,500.00"
  end

  test "user can view a monthly report" do
    # Assume a report already exists from previous test or fixtures
    visit "/monthly_reports"
    click_link "July 2023 Report"
    assert_current_path "/monthly_reports/1"
    assert_text "July 2023 Report"
    assert_text "Month: July"
    assert_text "Year: 2023"
    assert_text "Total Expenses: $1,500.00"
    assert_text "Travel"
    assert_text "$300.00"
    assert_text "Flight to conference"
  end

  test "user can edit a monthly report" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/"

    # Navigate to existing report
    visit "/monthly_reports"
    click_link "July 2023 Report"
    click_link "Edit"
    assert_current_path "/monthly_reports/1/edit"

    # Update report details
    fill_in "Notes", with: "Updated notes after review."
    click_button "Update Report"

    # Verify update
    assert_text "Report was successfully updated"
    assert_current_path "/monthly_reports/1"
    assert_text "Updated notes after review."
  end

  test "user can delete a monthly report" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/"

    # Navigate to reports list
    visit "/monthly_reports"
    assert_selector "tr", text: "July 2023 Report"

    # Delete the report
    accept_confirm do
      click_link "Destroy", match: :first
    end

    # Verify deletion
    assert_text "Report was successfully destroyed"
    assert_current_path "/monthly_reports"
    assert_no_selector "tr", text: "July 2023 Report"
  end
end
end
