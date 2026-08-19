require "application_system_test_case"

class DevCreateExpenseModelCrudTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class ExpenseTrackerTest < Capybara::SystemTestCase
  test "user can create a new expense" do
    visit "/expenses/new"
    fill_in "Description", with: "Grocery Shopping"
    fill_in "Amount", with: "50.00"
    select "Food", from: "Category"
    click_button "Create Expense"
    assert_text "Expense was successfully created."
    assert_text "Grocery Shopping"
    assert_current_path "/expenses"
  end

  test "user can view all expenses" do
    visit "/expenses"
    assert_selector ".expense-item"
    assert_text "Grocery Shopping"
  end

  test "user can edit an existing expense" do
    visit "/expenses/edit/1"
    fill_in "Description", with: "Updated Grocery Shopping"
    fill_in "Amount", with: "65.50"
    select "Entertainment", from: "Category"
    click_button "Update Expense"
    assert_text "Expense was successfully updated."
    assert_text "Updated Grocery Shopping"
    assert_current_path "/expenses"
  end

  test "user can delete an expense" do
    visit "/expenses"
    click_button "Delete"
    assert_text "Expense was successfully destroyed."
    assert_no_text "Grocery Shopping"
  end
end
end
