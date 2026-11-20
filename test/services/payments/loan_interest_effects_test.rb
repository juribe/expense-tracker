# frozen_string_literal: true

require "test_helper"

# The estimated loan interest is informational: payments and reconciliation
# keep moving only the principal, and the monthly reference day is never
# advanced implicitly. A payment with interest hides the estimate for the
# rest of that cycle.
class Payments::LoanInterestEffectsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Loan Payment Interest", email: "loan_payment_interest@example.com",
                         password: "password123")
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 5_000_000)
    @loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage", active: true)
    @loan.create_credit_account!(
      principal_amount: 20_000_000,
      outstanding_balance: 10_000_000,
      interest_rate: 18.05,
      interest_rate_type: "effective_annual",
      interest_calculation_enabled: true,
      interest_calculation_day: 1,
      start_date: Date.new(2025, 1, 1),
      payment_frequency: "monthly"
    )
    @category = Category.create!(user: @user, name: "Pagos")
    @calculation_date = Date.new(2026, 2, 10)
  end

  def create_payment(principal: 400_000, interest: 100_000, date: Date.new(2026, 1, 15))
    expense = @user.expenses.create!(
      category: @category, description: "Cuota hipoteca", amount: principal + interest,
      kind: "expense", source: "manual", date: date, money_source: @account
    )
    payment = Payment.create!(
      user: @user, expense: expense, money_source: @loan, amount: principal + interest,
      principal_amount: principal, interest_amount: interest
    )
    @loan.credit_account.reload
    payment
  end

  test "a payment reduces principal only by its recorded principal portion" do
    before = @loan.credit_account.reload.outstanding_balance
    estimate_before = @loan.estimated_accrued_interest(calculation_date: @calculation_date)

    payment = create_payment(principal: 400_000, interest: 100_000, date: Date.new(2026, 1, 15))

    assert_equal before - 400_000, @loan.credit_account.reload.outstanding_balance
    assert_equal BigDecimal("100000"), payment.reload.interest_amount
    assert_operator @loan.estimated_accrued_interest(calculation_date: @calculation_date), :<, estimate_before
  end

  test "a payment with interest covers the current cycle and is not persisted as an estimate" do
    assert_difference -> { Payment.count }, 1 do
      assert_difference -> { Expense.count }, 1 do
        create_payment(date: Date.new(2026, 2, 5))
      end
    end

    estimate = @loan.loan_interest_estimate(calculation_date: Date.new(2026, 2, 10))

    assert estimate.paid_in_cycle?
    assert_equal BigDecimal("0"), estimate.estimated_interest
    assert_equal BigDecimal("9600000"), estimate.estimated_total_balance

    assert_no_difference -> { Payment.count } do
      assert_no_difference -> { Expense.count } do
        @loan.estimated_total_balance(calculation_date: Date.new(2026, 2, 10))
      end
    end
  end

  test "the reference day is not advanced implicitly after a payment" do
    create_payment(date: Date.new(2026, 2, 5))

    assert_equal 1, @loan.credit_account.reload.interest_calculation_day
  end

  test "reconciliation still updates principal and leaves the estimate independent" do
    assert_no_difference -> { Payment.count } do
      Reconciliation::CheckBalance.call(
        user: @user, money_source: @loan, actual_balance: "9.000.000", adjust: true,
        note: "Saldo del banco"
      )
    end

    account = @loan.credit_account.reload
    assert_equal BigDecimal("9000000"), account.outstanding_balance
    assert_equal 1, account.interest_calculation_day
    assert account.interest_calculation_enabled?

    estimate = @loan.estimated_total_balance(calculation_date: @calculation_date)
    assert_operator estimate, :>, BigDecimal("9000000")
    assert_equal BigDecimal("9000000"), @loan.credit_account.reload.outstanding_balance
  end

  test "requesting the estimate does not touch reconciliation snapshots" do
    assert_no_difference -> { ReconciliationSnapshot.count } do
      @loan.estimated_total_balance(calculation_date: @calculation_date)
      @loan.loan_interest_estimate(calculation_date: @calculation_date)
    end
  end
end
