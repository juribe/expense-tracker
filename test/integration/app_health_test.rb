# frozen_string_literal: true

require "test_helper"

class AppHealthTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "health_test@example.com",
      password: "password123"
    )
  end

  test "database is connected and responsive" do
    assert_nothing_raised do
      ActiveRecord::Base.connection.execute("SELECT 1")
    end
  end

  test "main routes resolve correctly" do
    assert_equal "/dashboard", dashboard_path
    assert_equal "/expenses", expenses_path
    assert_equal "/categories", categories_path
  end

  test "GET /up health endpoint returns success" do
    get "/up"
    assert_response :success
  end

  test "expenses CRUD operations work" do
    sign_in @user
    category = Category.create!(name: "Health", is_default: true, category_type: "expense")

    # Create
    assert_difference("Expense.count", 1) do
      post expenses_path, params: {
        expense: {
          amount: 50.00,
          date: Date.today,
          category_id: category.id,
          description: "Pharmacy"
        }
      }
    end
    expense = Expense.last
    assert_equal(-50.00, expense.amount)
    assert_equal "Pharmacy", expense.description

    # Read
    get expense_path(expense)
    assert_response :success

    # Update
    patch expense_path(expense), params: {
      expense: { description: "CVS Pharmacy" }
    }
    expense.reload
    assert_equal "CVS Pharmacy", expense.description

    # Delete
    assert_difference("Expense.count", -1) do
      delete expense_path(expense)
    end
  end

  test "Devise authentication system is functional" do
    # Sign in works
    sign_in @user
    get expenses_path
    assert_response :success

    # Sign out works
    sign_out @user
    get expenses_path
    assert_response :redirect
  end

  test "User model is queryable" do
    assert_respond_to User, :count
    assert User.count >= 1
  end

  test "Expense model is queryable" do
    assert_respond_to Expense, :count
  end
end
