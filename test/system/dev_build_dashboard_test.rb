require "application_system_test_case"

class DevBuildDashboardTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class DashboardTest < ApplicationSystemTestCase
  test "user can view dashboard with expense summary" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"

    # Add a new expense
    click_link "Add Expense"
    assert_current_path "/expenses/new"
    fill_in "Amount", with: "50.00"
    fill_in "Description", with: "Groceries"
    select "Food", from: "Category"
    click_button "Create Expense"
    assert_text "Expense was successfully created"
    assert_current_path "/expenses"

    # Return to dashboard
    click_link "Dashboard"
    assert_current_path "/dashboard"

    # Verify dashboard content
    assert_text "Total Expenses"
    assert_selector "tr", text: "Groceries"
    assert_text "$50.00"
  end
end
end
