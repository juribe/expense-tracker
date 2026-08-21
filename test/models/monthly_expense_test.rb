# frozen_string_literal: true

require "test_helper"

class MonthlyExpenseTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Pay User", email: "monthly_expense_test@example.com", password: "password123")
    @category = Category.create!(name: "Car")
    @monthly_expense = MonthlyExpense.create!(
      user: @user,
      category: @category,
      amount: 2817.60,
      description: "Car Loan",
      payment_day: 15
    )
  end

  test "pay! creates a regular expense with the configured attributes" do
    payment_date = Date.new(2026, 8, 15)

    expense = @monthly_expense.pay!(payment_date: payment_date)

    assert_equal @user.id, expense.user_id
    assert_equal @category.id, expense.category_id
    assert_equal BigDecimal("2817.60"), expense.amount
    assert_equal "Car Loan", expense.description
    assert_equal payment_date, expense.date
    assert_equal "one_time", expense.frequency
  end

  test "pay! links the generated expense to the monthly expense via a payment record" do
    payment_date = Date.new(2026, 8, 15)

    expense = @monthly_expense.pay!(payment_date: payment_date)

    payment = @monthly_expense.monthly_expense_payments.sole
    assert_equal expense.id, payment.expense_id
    assert_equal payment_date, payment.payment_date
  end

  test "pay! uses an amount override when provided" do
    expense = @monthly_expense.pay!(payment_date: Date.new(2026, 8, 15), amount_override: 1000)

    assert_equal BigDecimal("1000"), expense.amount
  end

  test "pay! keeps the monthly expense active for future months" do
    @monthly_expense.pay!(payment_date: Date.new(2026, 8, 15))

    assert @monthly_expense.reload.active?
    assert_equal :pending, @monthly_expense.status_for(Date.new(2026, 9, 1))
  end

  test "pay! rejects a duplicate payment within the same month" do
    @monthly_expense.pay!(payment_date: Date.new(2026, 8, 15))

    assert_raises(MonthlyExpense::PaymentError) do
      @monthly_expense.pay!(payment_date: Date.new(2026, 8, 25))
    end

    assert_equal 1, @monthly_expense.monthly_expense_payments.count
    assert_equal 1, @user.expenses.count
  end

  test "pay! rolls back both records when the payment insert fails" do
    # Force the linked payment to be invalid by pre-creating a same-month
    # payment behind the model's back; the transaction must roll back the
    # generated Expense too.
    other_user = User.create!(name: "Other", email: "rollback_test@example.com", password: "password123")
    stale_payment = MonthlyExpensePayment.create!(
      monthly_expense: @monthly_expense,
      expense: other_user.expenses.create!(
        category: @category, amount: 1, date: Date.new(2026, 8, 1), frequency: "one_time"
      ),
      payment_date: Date.new(2026, 8, 20)
    )

    assert_raises(MonthlyExpense::PaymentError) do
      @monthly_expense.pay!(payment_date: Date.new(2026, 8, 15))
    end

    assert_not Expense.exists?(@user.expenses.where(category: @category).first&.id)
    assert_equal [ stale_payment ], @monthly_expense.monthly_expense_payments.to_a
  end

  test "pay! raises when the monthly expense is inactive" do
    @monthly_expense.update!(active: false)

    error = assert_raises(MonthlyExpense::PaymentError) do
      @monthly_expense.pay!(payment_date: Date.new(2026, 8, 15))
    end

    assert_match(/inactive/i, error.message)
    assert_equal 0, @user.expenses.count
  end

  test "paid_in_month? is true only for payments inside that month" do
    @monthly_expense.pay!(payment_date: Date.new(2026, 8, 15))

    assert @monthly_expense.paid_in_month?(Date.new(2026, 8, 1))
    assert @monthly_expense.paid_in_month?(Date.new(2026, 8, 31))
    assert_not @monthly_expense.paid_in_month?(Date.new(2026, 7, 31))
    assert_not @monthly_expense.paid_in_month?(Date.new(2026, 9, 1))
  end

  test "status_for reports paid once the current month has been paid" do
    assert_equal :pending, @monthly_expense.status_for(Date.current)
    @monthly_expense.pay!(payment_date: Date.current.beginning_of_month + 3)
    assert_equal :paid, @monthly_expense.status_for(Date.current)
  end

  test "suggested_payment_date clamps to the last day of short months" do
    @monthly_expense.update!(payment_day: 31)
    assert_equal Date.new(2026, 2, 28), @monthly_expense.suggested_payment_date(Date.new(2026, 2, 10))
    assert_equal Date.new(2026, 4, 30), @monthly_expense.suggested_payment_date(Date.new(2026, 4, 10))
    @monthly_expense.update!(payment_day: 15)
    assert_equal Date.new(2026, 8, 15), @monthly_expense.suggested_payment_date(Date.new(2026, 8, 10))
  end

  test "suggested_payment_date falls back to the month itself without a payment day" do
    @monthly_expense.update!(payment_day: nil)
    assert_equal Date.new(2026, 8, 1), @monthly_expense.suggested_payment_date(Date.new(2026, 8, 1))
  end

  test "validates amount is positive" do
    @monthly_expense.amount = 0
    assert_not @monthly_expense.valid?

    @monthly_expense.amount = -5
    assert_not @monthly_expense.valid?
  end

  test "validates payment_day is between 1 and 31" do
    @monthly_expense.payment_day = 0
    assert_not @monthly_expense.valid?

    @monthly_expense.payment_day = 32
    assert_not @monthly_expense.valid?

    @monthly_expense.payment_day = 15
    assert @monthly_expense.valid?
  end
end
