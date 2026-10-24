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
    category = Category.create!(name: "Hobby", user: @user, is_default: false, category_type: "expense")
    get categories_path
    assert_response :success
    assert_select "div.d-inline-flex a.btn-sm.btn-outline-primary", count: 1
    assert_select "div.d-inline-flex form button.btn-sm.btn-outline-danger", count: 1
  end

  test "GET /categories/new renders the form" do
    get new_category_path
    assert_response :success
    assert_select "form"
    assert_select "#category_name"
    assert_select "#category_category_type"
    assert_select "#category_description"
  end

  test "GET /categories defaults to the expense tab" do
    expense = Category.create!(name: "Mercado", user: @user, is_default: false, category_type: "expense")
    income = Category.create!(name: "Salario", user: @user, is_default: false, category_type: "income")

    get categories_path

    assert_response :success
    assert_select "ul.nav-tabs a.nav-link.active", text: /#{I18n.t("types.expense_plural")}/
    assert_select "a[href=?]", category_path(expense)
    assert_select "a[href=?]", category_path(income), count: 0
  end

  test "GET /categories with type=income shows only income categories" do
    expense = Category.create!(name: "Mercado", user: @user, is_default: false, category_type: "expense")
    income = Category.create!(name: "Salario", user: @user, is_default: false, category_type: "income")

    get categories_path(type: "income")

    assert_response :success
    assert_select "ul.nav-tabs a.nav-link.active", text: /#{I18n.t("types.income_plural")}/
    assert_select "a[href=?]", category_path(income)
    assert_select "a[href=?]", category_path(expense), count: 0
  end

  test "GET /categories falls back to expense for an unknown type" do
    get categories_path(type: "transfer")

    assert_response :success
    assert_select "ul.nav-tabs a.nav-link.active", text: /#{I18n.t("types.expense_plural")}/
  end

  test "GET /categories/new preselects the requested type" do
    get new_category_path(type: "income")

    assert_response :success
    assert_select "select#category_category_type option[selected][value=income]"
  end

  test "GET /categories/new offers a searchable parent category picker" do
    parent = Category.create!(name: "Comida", is_default: true, category_type: "expense")
    get new_category_path
    assert_response :success
    assert_select "[data-testid=category-parent-picker] [role=combobox]"
    assert_select "select#category_parent_id option[value=?]", parent.id.to_s
    assert_select "[data-testid=category-parent-picker] [role=option][data-value=?]", parent.id.to_s
  end

  test "POST /categories creates a custom category" do
    assert_difference("Category.count", 1) do
      post categories_path, params: { category: { name: "Food", description: "Meals", category_type: "expense" } }
    end
    category = Category.last
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

  test "PATCH /categories does not change the category type" do
    category = Category.create!(name: "Mercado", user: @user, is_default: false, category_type: "expense")

    patch category_path(category), params: { category: { category_type: "income" } }

    assert_equal "expense", category.reload.category_type
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
    assert_equal I18n.t("category_messages.only_own_edit"), flash[:alert]
  end

  test "cannot delete a default category" do
    category = Category.create!(name: "Locked", is_default: true, category_type: "expense")
    assert_no_difference("Category.count") do
      delete category_path(category)
    end
    assert_redirected_to categories_path
    assert_equal I18n.t("category_messages.only_own_delete"), flash[:alert]
  end

  test "POST /categories supports parent category" do
    parent = Category.create!(name: "Electronics", is_default: true, category_type: "expense")
    post categories_path, params: { category: { name: "Phones", parent_id: parent.id, category_type: "expense" } }
    assert_equal parent, Category.last.parent
  end

  test "GET /categories/:id renders the show of an own custom category" do
    category = Category.create!(name: "Propia", user: @user, is_default: false, category_type: "expense")

    get category_path(category)

    assert_response :success
    assert_select "h4", text: /Propia/
  end

  test "GET /categories/:id renders a shared default category" do
    category = Category.create!(name: "Compartida", is_default: true, category_type: "expense")

    get category_path(category)

    assert_response :success
    assert_select "h4", text: /Compartida/
  end

  test "GET /categories/:id does not reveal another user's custom category" do
    other = User.create!(name: "Other", email: "categories_foreign_show@example.com", password: "password123")
    foreign = Category.create!(name: "Privada Ajena", user: other, is_default: false,
                               category_type: "expense")

    get category_path(foreign)

    assert_redirected_to categories_path
    assert_equal I18n.t("category_messages.not_found"), flash[:alert]
  end

  test "POST /categories rejects a foreign custom parent" do
    other_user = User.create!(name: "Other", email: "categories_foreign_parent@example.com", password: "password123")
    foreign_parent = Category.create!(name: "Padre Ajeno", user: other_user, is_default: false,
                                      category_type: "expense")

    assert_no_difference "Category.count" do
      post categories_path, params: {
        category: { name: "Hija", parent_id: foreign_parent.id, category_type: "expense" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "PATCH /categories/:id rejects changing the parent to a foreign category" do
    own_parent = Category.create!(name: "Padre Propio", user: @user, is_default: false, category_type: "expense")
    child = Category.create!(name: "Hija", user: @user, is_default: false, category_type: "expense",
                             parent: own_parent)
    other_user = User.create!(name: "Other", email: "categories_foreign_parent_update@example.com",
                              password: "password123")
    foreign_parent = Category.create!(name: "Padre Ajeno", user: other_user, is_default: false,
                                      category_type: "expense")

    patch category_path(child), params: { category: { parent_id: foreign_parent.id } }

    assert_response :unprocessable_entity
    assert_equal own_parent, child.reload.parent
  end
end
