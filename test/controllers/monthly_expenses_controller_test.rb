# frozen_string_literal: true

require "test_helper"

class MonthlyExpensesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Monthly User",
      email: "monthly_expenses_controller_test@example.com",
      password: "password123"
    )
    @category = Category.create!(name: "Car")
    sign_in @user
  end

  def create_monthly_expense(user: @user, category: @category, amount: 2817.60)
    user.monthly_expenses.create!(
      category: category,
      amount: amount,
      description: "Car Loan",
      payment_day: 15
    )
  end

  test "GET /monthly_expenses renders the table with rows and pending status" do
    create_monthly_expense
    get monthly_expenses_path
    assert_response :success
    assert_select "[data-testid=table]"
    assert_select "tr[data-testid=row]", count: 1
    assert_select "[data-testid=status] .badge", text: "Pending"
    assert_select "[data-pay]", count: 1
  end

  test "GET /monthly_expenses shows paid status after paying this month" do
    monthly_expense = create_monthly_expense
    monthly_expense.pay!(payment_date: Date.current)

    get monthly_expenses_path
    assert_response :success
    assert_select "[data-testid=status] .badge", text: "Paid"
    assert_select "[data-pay]", count: 0
  end

  test "GET /monthly_expenses shows empty state when none exist" do
    get monthly_expenses_path
    assert_response :success
    assert_select "[data-testid=empty]"
    assert_select "tr[data-testid=row]", count: 0
  end

  test "GET /monthly_expenses/new renders the form" do
    get new_monthly_expense_path
    assert_response :success
    assert_select "form"
    assert_select "#monthly_expense_category_id"
    assert_select "#monthly_expense_amount"
    assert_select "#monthly_expense_payment_day"
  end

  test "GET /monthly_expenses/:id/edit renders the form" do
    monthly_expense = create_monthly_expense
    get edit_monthly_expense_path(monthly_expense)
    assert_response :success
    assert_select "form"
  end

  test "GET /monthly_expenses/:id renders the detail page with payment history" do
    monthly_expense = create_monthly_expense
    monthly_expense.pay!(payment_date: Date.new(2026, 8, 15))
    get monthly_expense_path(monthly_expense)
    assert_response :success
    assert_select "h4", text: "Monthly Expense"
    assert_select "td", text: "Aug 15, 2026"
  end

  test "POST /monthly_expenses creates a monthly expense" do
    assert_difference -> { MonthlyExpense.count }, 1 do
      post monthly_expenses_path, params: {
        monthly_expense: {
          category_id: @category.id, description: "Rent", amount: "1500.00",
          payment_day: "5", active: "1"
        }
      }
    end
    assert_redirected_to monthly_expenses_path

    record = MonthlyExpense.last
    assert_equal @user.id, record.user_id
    assert_equal "Rent", record.description
    assert_equal BigDecimal("1500.00"), record.amount
    assert_equal 5, record.payment_day
    assert record.active?
  end

  test "PATCH /monthly_expenses/:id updates the configuration" do
    monthly_expense = create_monthly_expense
    patch monthly_expense_path(monthly_expense), params: {
      monthly_expense: { amount: "3000.00", active: "0" }
    }
    assert_redirected_to monthly_expenses_path
    monthly_expense.reload
    assert_equal BigDecimal("3000.00"), monthly_expense.amount
    assert_not monthly_expense.active?
  end

  test "DELETE /monthly_expenses/:id destroys the configuration" do
    monthly_expense = create_monthly_expense
    assert_difference -> { MonthlyExpense.count }, -1 do
      delete monthly_expense_path(monthly_expense)
    end
    assert_redirected_to monthly_expenses_path
    assert_not MonthlyExpense.exists?(monthly_expense.id)
  end

  test "POST /monthly_expenses/:id/pay creates a regular expense with correct attributes" do
    monthly_expense = create_monthly_expense

    assert_difference -> { Expense.count }, 1 do
      post pay_monthly_expense_path(monthly_expense), params: {
        monthly_expense_payment: { payment_date: "2026-08-15", amount: "" }
      }
    end

    assert_redirected_to monthly_expenses_path
    expense = Expense.last
    assert_equal @user.id, expense.user_id
    assert_equal @category.id, expense.category_id
    assert_equal BigDecimal("2817.60"), expense.amount
    assert_equal "Car Loan", expense.description
    assert_equal Date.new(2026, 8, 15), expense.date
    assert_equal "one_time", expense.frequency

    payment = monthly_expense.monthly_expense_payments.sole
    assert_equal expense.id, payment.expense_id
    assert_equal Date.new(2026, 8, 15), payment.payment_date
  end

  test "POST /monthly_expenses/:id/pay honors an amount override" do
    monthly_expense = create_monthly_expense

    post pay_monthly_expense_path(monthly_expense), params: {
      monthly_expense_payment: { payment_date: "2026-08-15", amount: "2500.00" }
    }

    assert_redirected_to monthly_expenses_path
    assert_equal BigDecimal("2500.00"), Expense.last.amount
  end

  test "POST /monthly_expenses/:id/pay rejects duplicate payments for the same month" do
    monthly_expense = create_monthly_expense
    monthly_expense.pay!(payment_date: Date.new(2026, 8, 15))

    assert_no_difference -> { Expense.count } do
      post pay_monthly_expense_path(monthly_expense), params: {
        monthly_expense_payment: { payment_date: "2026-08-25", amount: "" }
      }
    end

    assert_redirected_to monthly_expenses_path
    assert_match(/already paid/i, flash[:alert])
    assert_equal 1, monthly_expense.monthly_expense_payments.count
  end

  test "POST /monthly_expenses/:id/pay rejects payments on inactive configurations" do
    monthly_expense = create_monthly_expense
    monthly_expense.update!(active: false)

    assert_no_difference -> { Expense.count } do
      post pay_monthly_expense_path(monthly_expense), params: {
        monthly_expense_payment: { payment_date: "2026-08-15", amount: "" }
      }
    end

    assert_redirected_to monthly_expenses_path
    assert_match(/inactive/i, flash[:alert])
  end

  test "another user cannot manage or pay someone else's monthly expense" do
    monthly_expense = create_monthly_expense
    intruder = User.create!(
      name: "Intruder",
      email: "monthly_intruder_test@example.com",
      password: "password123"
    )
    sign_in intruder

    # Owner-scoped find raises, which the app renders as an error response.
    post pay_monthly_expense_path(monthly_expense), params: {
      monthly_expense_payment: { payment_date: "2026-08-15", amount: "" }
    }
    assert_response :error

    patch monthly_expense_path(monthly_expense),
          params: { monthly_expense: { amount: "1.00" } }
    assert_response :error

    delete monthly_expense_path(monthly_expense)
    assert_response :error

    assert_equal 0, intruder.expenses.count
    assert_equal 0, monthly_expense.monthly_expense_payments.count
    monthly_expense.reload
    assert_equal BigDecimal("2817.60"), monthly_expense.amount
    assert MonthlyExpense.exists?(monthly_expense.id)
  end
end
