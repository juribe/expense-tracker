# frozen_string_literal: true

require "test_helper"

class RecurringTransactionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Ctrl User", email: "rt_controller@example.com", password: "password123")
    @other_user = User.create!(name: "Other Ctrl", email: "rt_controller_other@example.com", password: "password123")
    @category = Category.create!(name: "Salary Ctrl")
    sign_in @user
  end

  test "GET /recurring_transactions renders the income tab" do
    get recurring_transactions_path
    assert_response :success
    assert_match "Recurring Transactions", response.body
    assert_match "Add Recurring", response.body
  end

  test "GET /recurring_transactions?type=expense renders the expense tab" do
    get recurring_transactions_path(type: "expense")
    assert_response :success
    assert_match 'class="nav-link active"', response.body
  end

  test "POST creates a recurring income for the current user" do
    assert_difference -> { @user.recurring_transactions.count }, 1 do
      post recurring_transactions_path, params: {
        recurring_transaction: {
          category_id: @category.id,
          transaction_type: "income",
          amount: 6500,
          description: "Freelance Job",
          payment_day: 15,
          active: true
        }
      }
    end

    assert_redirected_to recurring_transactions_path(type: "income")
    rt = @user.recurring_transactions.last
    assert_equal "income", rt.transaction_type
    assert_equal BigDecimal("6500"), rt.amount
  end

  test "POST with invalid data re-renders the page" do
    post recurring_transactions_path, params: {
      recurring_transaction: { category_id: @category.id, transaction_type: "income", amount: -1, payment_day: 15 }
    }

    assert_response :unprocessable_entity
  end

  test "PATCH updates the recurring transaction but not its type" do
    rt = RecurringTransaction.create!(
      user: @user, category: @category, transaction_type: "income",
      amount: 100, payment_day: 5
    )

    patch recurring_transaction_path(rt), params: {
      recurring_transaction: { amount: 250, description: "Updated", transaction_type: "expense" }
    }

    assert_redirected_to recurring_transactions_path(type: "income")
    rt.reload
    assert_equal BigDecimal("250"), rt.amount
    assert_equal "Updated", rt.description
    assert_equal "income", rt.transaction_type
  end

  test "DELETE removes the recurring transaction" do
    rt = RecurringTransaction.create!(
      user: @user, category: @category, transaction_type: "expense",
      amount: 100, payment_day: 5
    )

    assert_difference -> { RecurringTransaction.count }, -1 do
      delete recurring_transaction_path(rt)
    end

    assert_redirected_to recurring_transactions_path(type: "expense")
  end

  test "POST process_transaction on income creates a one_time Income and occurrence" do
    rt = RecurringTransaction.create!(
      user: @user, category: @category, transaction_type: "income",
      amount: 6500, description: "Salary", payment_day: 15
    )

    assert_difference -> { Income.count }, 1 do
      assert_difference -> { RecurringTransactionOccurrence.count }, 1 do
        post process_transaction_recurring_transaction_path(rt),
             params: { amount: "6800", date: "2026-08-18" }
      end
    end

    assert_redirected_to recurring_transactions_path(type: "income")
    income = Income.last
    assert_equal @user.id, income.user_id
    assert_equal BigDecimal("6800"), income.amount
    assert_equal Date.new(2026, 8, 18), income.date
    assert_equal "one_time", income.frequency
    assert rt.reload.active?
  end

  test "POST process_transaction on expense creates a one_time Expense" do
    rt = RecurringTransaction.create!(
      user: @user, category: @category, transaction_type: "expense",
      amount: 1200, description: "Car Loan", payment_day: 10
    )

    assert_difference -> { Expense.count }, 1 do
      post process_transaction_recurring_transaction_path(rt),
           params: { amount: "1200", date: "2026-08-15" }
    end

    assert_equal "Expense", Expense.last.class.name
    assert_equal "one_time", Expense.last.frequency
  end

  test "POST process_transaction rejects duplicate processing for the same month" do
    rt = RecurringTransaction.create!(
      user: @user, category: @category, transaction_type: "income",
      amount: 100, payment_day: 1
    )
    post process_transaction_recurring_transaction_path(rt), params: { amount: "100", date: "2026-08-01" }

    assert_no_difference -> { Income.count } do
      post process_transaction_recurring_transaction_path(rt), params: { amount: "100", date: "2026-08-20" }
    end

    assert_redirected_to recurring_transactions_path(type: "income")
    follow_redirect!
    assert_match(/Already processed/i, flash[:alert])
  end

  test "PATCH toggle_active deactivates and reactivates" do
    rt = RecurringTransaction.create!(
      user: @user, category: @category, transaction_type: "income",
      amount: 100, payment_day: 1
    )

    patch toggle_active_recurring_transaction_path(rt)
    refute rt.reload.active?

    patch toggle_active_recurring_transaction_path(rt)
    assert rt.reload.active?
  end

  test "users cannot manage another user's recurring transactions" do
    other_rt = RecurringTransaction.create!(
      user: @other_user, category: @category, transaction_type: "income",
      amount: 100, payment_day: 1
    )

    # Owner-only scoping means the lookup never finds the record; the app's
    # global error handling turns the miss into an error response.
    patch recurring_transaction_path(other_rt), params: { recurring_transaction: { amount: 999 } }
    assert_response :error

    delete recurring_transaction_path(other_rt)
    assert_response :error

    post process_transaction_recurring_transaction_path(other_rt), params: { amount: "1", date: "2026-08-01" }
    assert_response :error

    assert_equal 100, other_rt.reload.amount
    assert_empty other_rt.occurrences
    assert_empty Income.where(user: @other_user)
  end

  test "guests are redirected to sign in" do
    sign_out @user
    get recurring_transactions_path
    assert_redirected_to new_user_session_path
  end

  test "new, edit and show routes are not routed (modal-based CRUD)" do
    # With show_exceptions = :rescuable in tests, unrouted paths render a 404
    # page instead of raising ActionController::RoutingError.
    get "/recurring_transactions/new"
    assert_response :not_found

    rt = @user.recurring_transactions.create!(
      user: @user, category: @category, transaction_type: "income", amount: 1, payment_day: 1
    )
    get recurring_transaction_path(rt)
    assert_response :not_found
  end
end
