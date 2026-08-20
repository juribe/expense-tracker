require "application_system_test_case"

class DevAddMonthlyReportsTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  RSpec.describe "Monthly Reports", type: :system do
  before do
    # Assuming a helper method for authentication exists
    login_as("test@example.com", "password123")
  end
  test "user can generate a monthly report for expenses" do
    visit "/reports/new"
    select "January", from: "Month"
    select "2023", from: "Year"
    click_button "Generate Report"
    assert_current_path "/reports/monthly?month=January&year=2023"
    assert_text "Monthly Expense Report for January 2023"
    assert_selector ".expense-summary-table"
    assert_text "Total Spending: $1,250.00"
  end
  test "user can view a report with no data" do
    visit "/reports/new"
    select "February", from: "Month"
    select "2023", from: "Year"
    click_button "Generate Report"
    assert_text "No expenses found for this period."
  end
  test "user can export monthly report to PDF" do
    visit "/reports/monthly?month=January&year=2023"
    click_link "Download PDF"
    assert_text "Downloading report..."
  end
end
end
