require "application_system_test_case"

class DevCreateCategoryModelCrudTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(
      name: "Test User",
      email: "category_crud@example.com",
      password: "password123"
    )
    visit "/users/sign_in"
    fill_in "Email", with: @user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
    assert_text "Signed in successfully"
  end

  test "user can create a category" do
    visit "/categories"
    click_link "New Category", match: :first
    assert_current_path "/categories/new"

    fill_in "Name", with: "Food"
    fill_in "Description", with: "Expenses for meals and groceries"
    click_button "Save Category"

    assert_current_path %r{\/categories\/\d+}
    assert_text "Category was successfully created"
    assert_text "Food"
  end

  test "user can edit a category" do
    Category.create!(name: "Transport", description: "Travel expenses")

    visit "/categories"
    find("a[aria-label='Edit Transport']").click
    assert_current_path %r{\/categories\/\d+\/edit}

    fill_in "Name", with: "Transportation"
    fill_in "Description", with: "All travel related costs"
    click_button "Save Category"

    assert_current_path %r{\/categories\/\d+}
    assert_text "Category was successfully updated"
    assert_text "Transportation"
  end

  test "user can delete a category" do
    Category.create!(name: "Entertainment", description: "Movies, concerts, etc.")

    visit "/categories"
    find("button[aria-label='Delete Entertainment']").click

    assert_text "Category was successfully destroyed"
    assert_no_text "Entertainment"
    assert_current_path "/categories"
  end

  test "user sees validation errors on submit" do
    Category.create!(name: "Food")

    visit "/categories/new"
    fill_in "Name", with: "Food"
    click_button "Save Category"

    assert_text "Name has already been taken"
    assert_selector "#error-summary"
    assert_selector "input.is-invalid"
  end
end
