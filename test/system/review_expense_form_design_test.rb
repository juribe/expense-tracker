require "application_system_test_case"

class ReviewExpenseFormDesignTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class ExpenseTrackerTest < ApplicationSystemTestCase
  test "user can create a new expense" do
    # Log in
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "Signed in successfully"
    assert_current_path "/dashboard"

    # Navigate to new expense form
    click_link "New Expense"
    assert_current_path "/expenses/new"

    # Fill out the expense form
    fill_in "Amount", with: "123.45"
    fill_in "Description", with: "Business lunch with client"
    select "Food", from: "Category"
    fill_in "Date", with: "2023-09-15"
    click_button "Create Expense"

    # Verify creation
    assert_text "Expense was successfully created"
    assert_current_path "/expenses"
    assert_selector "tr", text: "Business lunch with client"
    assert_selector "tr", text: "$123.45"
  end

  test "user can edit an existing expense" do
    # Log in
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"

    # Assume an expense exists; navigate to its edit page
    visit "/expenses"
    click_link "Edit", match: :first
    assert_current_path %r{^/expenses/\d+/edit$}

    # Update the expense
    fill_in "Amount", with: "150.00"
    fill_in "Description", with: "Updated business dinner"
    select "Entertainment", from: "Category"
    click_button "Update Expense"

    # Verify update
    assert_text "Expense was successfully updated"
    assert_current_path "/expenses"
    assert_selector "tr", text: "Updated business dinner"
    assert_selector "tr", text: "$150.00"
  end

  test "user sees validation errors when required fields are missing" do
    # Log in
    visit "/login"
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_current_path "/dashboard"

    # Attempt to create an expense with missing fields
    click_link "New Expense"
    fill_in "Amount", with: ""
    fill_in "Description", with: ""
    click_button "Create Expense"

    # Verify validation messages
    assert_text "Amount can't be blank"
    assert_text "Description can't be blank"
    assert_current_path "/expenses"
  end
end
end
