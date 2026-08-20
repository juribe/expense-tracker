require "application_system_test_case"

class DevCreateCategoryModelCrudTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  class CategoriesTest < ApplicationSystemTestCase
  test "user can create a category" do
    visit "/categories"
    click_link "New Category"
    assert_current_path "/categories/new"

    fill_in "Name", with: "Food"
    fill_in "Description", with: "Expenses for meals and groceries"
    fill_in "Budget", with: "500"
    select "Expense", from: "Category Type"
    click_button "Create Category"

    assert_text "Category was successfully created"
    assert_text "Food"
    assert_current_path "/categories"
  end

  test "user can edit a category" do
    # Create a category first
    visit "/categories"
    click_link "New Category"
    fill_in "Name", with: "Transport"
    fill_in "Description", with: "Travel expenses"
    fill_in "Budget", with: "200"
    select "Expense", from: "Category Type"
    click_button "Create Category"
    assert_text "Category was successfully created"

    # Edit the newly created category
    click_link "Edit", match: :first
    assert_current_path %r{\/categories\/\d+\/edit}

    fill_in "Name", with: "Transportation"
    fill_in "Description", with: "All travel related costs"
    fill_in "Budget", with: "300"
    select "Expense", from: "Category Type"
    click_button "Update Category"

    assert_text "Category was successfully updated"
    assert_text "Transportation"
    assert_current_path "/categories"
  end

  test "user can delete a category" do
    # Create a category to delete
    visit "/categories"
    click_link "New Category"
    fill_in "Name", with: "Entertainment"
    fill_in "Description", with: "Movies, concerts, etc."
    fill_in "Budget", with: "150"
    select "Expense", from: "Category Type"
    click_button "Create Category"
    assert_text "Category was successfully created"

    # Delete the category
    accept_confirm do
      click_link "Destroy", match: :first
    end

    assert_text "Category was successfully destroyed"
    assert_no_selector "td", text: "Entertainment"
    assert_current_path "/categories"
  end
end
end
