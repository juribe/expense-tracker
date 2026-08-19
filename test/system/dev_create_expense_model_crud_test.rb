require "application_system_test_case"

class DevCreateExpenseModelCrudTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class ExpenseCrudTest < ApplicationSystemTestCase
  test "user can create an expense" do
    visit "/expenses/new"
    fill_in "Amount", with: "50.00"
    select "Food", from: "Category"
    fill_in "Date", with: "2023-08-01"
    fill_in "Description", with: "Lunch at cafe"
    click_button "Create Expense"
    assert_text "Expense was successfully created."
    assert_current_path "/expenses"
  end

  test "user can view an expense" do
    visit "/expenses"
    click_link "Show", match: :first
    assert_text "Lunch at cafe"
    assert_text "50.00"
    assert_text "Food"
    assert_text "2023-08-01"
    assert_current_path %r{/expenses/\d+}
  end

  test "user can update an expense" do
    visit "/expenses"
    click_link "Edit", match: :first
    fill_in "Amount", with: "60.00"
    select "Travel", from: "Category"
    fill_in "Description", with: "Taxi"
    click_button "Update Expense"
    assert_text "Expense was successfully updated."
    assert_text "60.00"
    assert_text "Travel"
    assert_text "Taxi"
    assert_current_path %r{/expenses/\d+}
  end

  test "user can delete an expense" do
    visit "/expenses"
    click_link "Delete", match: :first
    page.driver.browser.switch_to.alert.accept
    assert_text "Expense was successfully destroyed."
    assert_current_path "/expenses"
    assert_no_selector "td", text: "Lunch at cafe"
  end
end
end
