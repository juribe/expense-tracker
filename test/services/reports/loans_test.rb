# frozen_string_literal: true

require "test_helper"

class ReportsLoansTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Loans User", email: "reports_loans_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @mortgage = @user.money_sources.create!(name: "Mortgage", kind: "loan", active: true)
    @mortgage.create_credit_account!(
      principal_amount: 100_000_000, outstanding_balance: 80_000_000,
      installment_amount: 1_500_000, installment_count: 60, installments_paid: 18,
      interest_rate: 9.5, interest_rate_type: "effective_annual", payment_frequency: "monthly",
      start_date: Date.new(2025, 3, 1)
    )
    @vehicle = @user.money_sources.create!(name: "Vehicle Loan", kind: "loan", active: true)
    @vehicle.create_credit_account!(
      principal_amount: 20_000_000, outstanding_balance: 10_000_000, installment_amount: 900_000
    )
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def loan_expense(amount, date: Date.new(2026, 9, 10))
    Expense.create!(user: @user, category: @food, money_source: @bank, amount: amount,
                    date: date, description: "x")
  end

  def loan_payment(source, expense, principal:, interest: 0, insurance: 0, other: 0)
    Payment.create!(user: @user, expense: expense, money_source: source, amount: expense.amount.abs,
                    principal_amount: principal, interest_amount: interest,
                    insurance_amount: insurance, other_amount: other)
  end

  def report
    Reports::Loans.new(user: @user, filter: @filter).call
  end

  test "reports per loan balance, installment and rate" do
    row = report[:rows].find { |r| r[:name] == "Mortgage" }

    assert_equal 80_000_000.to_d, row[:balance]
    assert_equal 1_500_000.to_d, row[:installment_amount]
    assert_equal "9.50% EA", row[:interest_rate_label]
    assert_equal 60, row[:installment_count]
  end

  test "aggregates the period's principal and interest per loan" do
    loan_payment(@mortgage, loan_expense(-1_500_000), principal: 1_200_000, interest: 280_000, insurance: 20_000)
    loan_payment(@vehicle, loan_expense(-900_000), principal: 750_000, interest: 150_000)

    row = report[:rows].find { |r| r[:name] == "Mortgage" }

    assert_equal 1_500_000.to_d, row[:paid]
    assert_equal 1_200_000.to_d, row[:principal_paid]
    assert_equal 280_000.to_d, row[:interest_paid]
    assert_equal 20_000.to_d, row[:insurance_paid]
    assert_equal 750_000.to_d, report[:rows].find { |r| r[:name] == "Vehicle Loan" }[:principal_paid]
  end

  test "consolidates debt totals for the period" do
    loan_payment(@mortgage, loan_expense(-1_500_000), principal: 1_200_000, interest: 280_000, insurance: 20_000)
    loan_payment(@vehicle, loan_expense(-900_000), principal: 750_000, interest: 150_000)

    data = report

    assert_equal 88_050_000.to_d, data[:total_debt], "outstanding drops as principal is repaid"
    assert_equal 1_950_000.to_d, data[:principal_paid]
    assert_equal 430_000.to_d, data[:interest_paid]
    assert_equal 2_400_000.to_d, data[:total_paid]
  end

  test "transfers into a loan count as debt payments" do
    @user.transfers.create!(from_source: @bank, to_source: @mortgage, amount: 700_000,
                            date: Date.new(2026, 9, 20))

    data = report

    assert_equal 700_000.to_d, data[:total_paid]
    assert_equal 700_000.to_d, data[:principal_paid]
    assert_equal 1, data[:total_payments_count]
  end

  test "loan disbursement transfer is not a debt payment" do
    @user.transfers.create!(from_source: @mortgage, to_source: @bank, amount: 5_000_000,
                            date: Date.new(2026, 9, 1))

    data = report

    assert_equal 0.to_d, data[:total_paid]
  end

  test "principal repayment is never an expense" do
    installment = loan_expense(-1_500_000)
    loan_payment(@mortgage, installment, principal: 1_500_000)

    data = report
    overview = Reports::Overview.new(user: @user, filter: @filter).call

    assert_equal 1_500_000.to_d, data[:total_paid]
    assert_equal 0.to_d, overview[:expenses][:total]
  end

  test "respects the loan filter" do
    loan_payment(@mortgage, loan_expense(-1_500_000), principal: 1_200_000, interest: 300_000)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, loan_id: @mortgage.id)

    data = Reports::Loans.new(user: @user, filter: scoped_filter).call

    assert_equal 1, data[:rows].size
    assert_equal 78_800_000.to_d, data[:total_debt]
  end

  test "next payment uses the loan's recurring template payment day" do
    @mortgage.recurring_templates.create!(user: @user, category: @food, kind: "expense", amount: 1_500_000,
                                          frequency: "monthly", payment_day: 5, active: true)

    row = report[:rows].find { |r| r[:name] == "Mortgage" }

    assert_equal Date.new(2026, 10, 5), row[:next_payment_date]
  end

  test "next payment derives from start date and frequency without a template" do
    row = report[:rows].find { |r| r[:name] == "Vehicle Loan" }

    assert_nil row[:next_payment_date], "no frequency set, no fabricated date"
  end

  test "empty period yields zeros with current balances" do
    data = report

    assert_equal 90_000_000.to_d, data[:total_debt]
    assert_equal 0.to_d, data[:total_paid]
  end

  test "loan without credit account data shows nils" do
    @user.money_sources.create!(name: "Bare Loan", kind: "loan", active: true)

    row = report[:rows].find { |r| r[:name] == "Bare Loan" }

    assert_nil row[:balance]
    assert_nil row[:installment_amount]
  end
end
