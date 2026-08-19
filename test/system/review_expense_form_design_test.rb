require "application_system_test_case"

class ReviewExpenseFormDesignTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class ExpenseFormDesignTest < ApplicationSystemTestCase
  test "user can create, edit, and view an expense" do
    # Sign in
    visit "/users/sign_in"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "Signed in successfully"
    assert_current_path "/"

    # Create a new expense
    visit "/expenses/new"
    fill_in "Title", with: "Lunch with client"
    fill_in "Amount", with: "45.67"
    fill_in "Date", with: "2023-09-15"
    select "Meals", from: "Category"
    fill_in "Notes", with: "Business lunch at downtown cafe"
    click_button "Create Expense"
    assert_text "Expense was successfully created."
    assert_selector "h1", text: "Lunch with client"
    expense_path = current_path
    assert_current_path expense_path

    # Edit the expense
    click_link "Edit"
    fill_in "Amount", with: "50.00"
    click_button "Update Expense"
    assert_text "Expense was successfully updated."
    assert_text "$50.00"

    # Return to the expenses index
    click_link "Back"
    assert_current_path "/expenses"
    assert_text "Lunch with client"
    assert_selector "td", text: "$50.00"
  end
end
end
