# frozen_string_literal: true

require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "categories_test@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "GET /categories/index renders the page with default and custom sections" do
    get categories_path
    assert_response :success
  end

  test "GET /categories/new renders the form" do
    get new_category_path
    assert_response :success
    assert_select "form"
    assert_select "#category_name"
    assert_select "#category_slug"
    assert_select "#category_category_type"
    assert_select "#category_description"
  end

  test "POST /categories creates a custom category and auto-generates slug" do
    assert_difference("Category.count", 1) do
      post categories_path, params: { category: { name: "Food", description: "Meals", category_type: "expense" } }
    end
    category = Category.last
    assert_equal "food", category.slug
    assert category.active?
    assert_not category.is_default?
    assert_equal @user, category.user
    assert_equal "expense", category.category_type
    assert_redirected_to category_path(category)
  end

  test "POST /categories with invalid params re-renders the form with errors" do
    assert_no_difference("Category.count") do
      post categories_path, params: { category: { name: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "#error-summary"
    assert_select "div.invalid-feedback"
  end

  test "PATCH /categories updates a custom category" do
    category = Category.create!(name: "Transport", user: @user, is_default: false, category_type: "expense")
    patch category_path(category), params: { category: { name: "Transportation", active: "0" } }
    category.reload
    assert_equal "Transportation", category.name
    assert_not category.active?
    assert_redirected_to category_path(category)
  end

  test "DELETE /categories destroys a custom category" do
    category = Category.create!(name: "Entertainment", user: @user, is_default: false, category_type: "expense")
    assert_difference("Category.count", -1) do
      delete category_path(category)
    end
    assert_redirected_to categories_path
  end

  test "cannot edit a default category" do
    category = Category.create!(name: "Locked", is_default: true, category_type: "expense")
    get edit_category_path(category)
    assert_redirected_to categories_path
    assert_equal "You can only edit your own categories.", flash[:alert]
  end

  test "cannot delete a default category" do
    category = Category.create!(name: "Locked", is_default: true, category_type: "expense")
    assert_no_difference("Category.count") do
      delete category_path(category)
    end
    assert_redirected_to categories_path
    assert_equal "You can only delete your own categories.", flash[:alert]
  end

  test "POST /categories supports parent category" do
    parent = Category.create!(name: "Electronics", is_default: true, category_type: "expense")
    post categories_path, params: { category: { name: "Phones", parent_id: parent.id, category_type: "expense" } }
    assert_equal parent, Category.last.parent
  end
end
