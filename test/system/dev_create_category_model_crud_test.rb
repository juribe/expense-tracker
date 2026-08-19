require "application_system_test_case"

class DevCreateCategoryModelCrudTest < ApplicationSystemTestCase
  setup do
    # Any setup needed before each test
  end
  
  require "application_system_test_case"

class CategoryCrudTest < ApplicationSystemTestCase
  test "user can create a new category" do
    visit "/categories/new"
    fill_in "Name", with: "Food & Dining"
    fill_in "Icon", with: "utensils"
    select "Essential", from: "Type"
    click_button "Create Category"

    assert_text "Category was successfully created."
    assert_current_path "/categories"
    assert_text "Food & Dining"
  end

  test "user can view category details" do
    visit "/categories/1"
    assert_text "Food & Dining"
    assert_text "Essential"
  end

  test "user can edit a category" do
    visit "/categories/1/edit"
    fill_in "Name", with: "Groceries"
    select "Variable", from: "Type"
    click_button "Update Category"

    assert_text "Category was successfully updated."
    assert_current_path "/categories/1"
    assert_text "Groceries"
  end

  test "user can delete a category" do
    visit "/categories"
    assert_selector ".category-item", text: "Food & Dining"
    
    accept_confirm do
      click_button "Delete"
    end

    assert_text "Category was successfully destroyed."
    assert_text "Food & Dining" # Should no longer be visible if using JS/AJAX or check via selector
  end
end
end
