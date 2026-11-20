# frozen_string_literal: true

require "test_helper"

class MoneySourceLoanInterestTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Loan Interest User", email: "loan_interest_model@example.com",
                         password: "password123")
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 5_000_000)
    @category = Category.create!(user: @user, name: "Pagos")
  end

  def create_loan(active: true, enabled: true, day: 11, start_date: Date.new(2025, 1, 11),
                  outstanding_balance: 10_000_000, rate: 18.05, rate_type: "effective_annual", **opts)
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage", active: active)
    loan.create_credit_account!(
      {
        principal_amount: 20_000_000,
        outstanding_balance: outstanding_balance,
        interest_rate: rate,
        interest_rate_type: rate_type,
        interest_calculation_enabled: enabled,
        interest_calculation_day: day,
        start_date: start_date,
        payment_frequency: "monthly"
      }.merge(opts)
    )
    loan
  end

  def create_payment(loan, date:, principal: 400_000, interest: 100_000)
    expense = @user.expenses.create!(
      category: @category, description: "Cuota hipoteca", amount: principal + interest,
      kind: "expense", source: "manual", date: date, money_source: @account
    )
    payment = Payment.create!(
      user: @user, expense: expense, money_source: loan, amount: principal + interest,
      principal_amount: principal, interest_amount: interest
    )
    loan.credit_account.reload
    payment
  end

  test "enabled loans expose estimated accrued interest and total balance" do
    loan = create_loan
    calculation_date = Date.new(2026, 11, 20)

    estimate = loan.loan_interest_estimate(calculation_date: calculation_date)

    assert estimate.calculated?
    assert_equal Date.new(2026, 11, 11), estimate.cycle_start_date
    assert_equal 9, estimate.elapsed_days
    assert_operator estimate.estimated_interest, :>, 0
    assert_equal loan.outstanding_balance + estimate.estimated_interest, estimate.estimated_total_balance
    assert_equal estimate.estimated_interest, loan.estimated_accrued_interest(calculation_date: calculation_date)
    assert_equal estimate.estimated_total_balance, loan.estimated_total_balance(calculation_date: calculation_date)
  end

  test "calculating the estimate never modifies the principal balance" do
    loan = create_loan

    assert_no_difference -> { loan.credit_account.reload.outstanding_balance } do
      loan.estimated_total_balance(calculation_date: Date.new(2026, 11, 20))
    end

    assert_equal BigDecimal("10000000"), loan.credit_account.reload.outstanding_balance
  end

  test "a payment with interest covers the current cycle" do
    loan = create_loan
    create_payment(loan, date: Date.new(2026, 11, 15), principal: 400_000, interest: 100_000)

    estimate = loan.loan_interest_estimate(calculation_date: Date.new(2026, 11, 20))

    assert estimate.paid_in_cycle?
    assert_equal BigDecimal("0"), estimate.estimated_interest
    assert_equal loan.outstanding_balance, estimate.estimated_total_balance
    assert_equal Date.new(2026, 12, 11), estimate.next_cycle_date
    assert_equal BigDecimal("0"), loan.estimated_accrued_interest(calculation_date: Date.new(2026, 11, 20))
  end

  test "the next cycle starts calculating again" do
    loan = create_loan
    create_payment(loan, date: Date.new(2026, 11, 15))

    assert_equal BigDecimal("0"),
                 loan.estimated_accrued_interest(calculation_date: Date.new(2026, 12, 11))
    assert_operator loan.estimated_accrued_interest(calculation_date: Date.new(2026, 12, 12)), :>, 0
  end

  test "a principal-only payment does not cover interest" do
    loan = create_loan
    create_payment(loan, date: Date.new(2026, 11, 15), principal: 500_000, interest: 0)

    estimate = loan.loan_interest_estimate(calculation_date: Date.new(2026, 11, 20))

    assert estimate.calculated?
    assert_operator estimate.estimated_interest, :>, 0
  end

  test "a payment before the current cycle does not suppress it" do
    loan = create_loan
    create_payment(loan, date: Date.new(2026, 11, 5), interest: 100_000)

    estimate = loan.loan_interest_estimate(calculation_date: Date.new(2026, 11, 20))

    assert estimate.calculated?
    assert_operator estimate.estimated_interest, :>, 0
  end

  test "deleting the interest payment recalculates the estimate" do
    loan = create_loan
    payment = create_payment(loan, date: Date.new(2026, 11, 15), interest: 100_000)

    assert loan.loan_interest_estimate(calculation_date: Date.new(2026, 11, 20)).paid_in_cycle?

    payment.destroy!

    assert loan.loan_interest_estimate(calculation_date: Date.new(2026, 11, 20)).calculated?
  end

  test "disabled loans do not expose an estimate" do
    loan = create_loan(enabled: false)

    estimate = loan.loan_interest_estimate(calculation_date: Date.new(2026, 11, 20))

    assert_equal :disabled, estimate.status
    assert_nil loan.estimated_accrued_interest(calculation_date: Date.new(2026, 11, 20))
  end

  test "inactive loans do not accrue interest" do
    loan = create_loan(active: false)

    estimate = loan.loan_interest_estimate(calculation_date: Date.new(2026, 11, 20))

    assert_equal :inactive, estimate.status
    assert_nil loan.estimated_accrued_interest(calculation_date: Date.new(2026, 11, 20))
  end

  test "loans without a reference day do not invent an estimate" do
    loan = create_loan(day: nil, start_date: nil)

    estimate = loan.loan_interest_estimate(calculation_date: Date.new(2026, 11, 20))

    assert_equal :missing_reference_day, estimate.status
    assert_nil loan.estimated_total_balance(calculation_date: Date.new(2026, 11, 20))
  end

  test "loans without a credit account expose no estimate" do
    loan = @user.money_sources.create!(name: "Bare Loan", kind: "loan", active: true)

    assert_equal :not_configured, loan.loan_interest_estimate.status
    assert_nil loan.estimated_accrued_interest
  end

  test "non-loan sources never accrue loan interest" do
    assert_equal :not_a_loan, @account.loan_interest_estimate.status
  end

  test "new loans default to monthly payment frequency" do
    loan = @user.money_sources.create!(name: "Nuevo préstamo", kind: "loan", active: true)
    loan.create_credit_account!(outstanding_balance: 10_000_000, interest_rate: 12)

    assert_equal "monthly", loan.credit_account.reload.payment_frequency
  end

  test "a blank reference day is filled from the first payment date" do
    loan = create_loan(day: nil, start_date: Date.new(2026, 1, 15))

    assert_equal 15, loan.credit_account.reload.interest_calculation_day
  end

  test "an existing reference day is never overwritten" do
    loan = create_loan(day: 10, start_date: Date.new(2026, 1, 15))

    assert_equal 10, loan.credit_account.reload.interest_calculation_day
  end

  test "a first payment date on the 31st fills day 30" do
    loan = create_loan(day: nil, start_date: Date.new(2026, 1, 31))

    assert_equal 30, loan.credit_account.reload.interest_calculation_day
  end

  test "a manually selected day 31 is stored as 30" do
    loan = create_loan(day: 31)

    assert_equal 30, loan.credit_account.reload.interest_calculation_day
  end
end
