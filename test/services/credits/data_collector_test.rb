# frozen_string_literal: true

require "test_helper"

# Credits::DataCollector gathers the projection inputs from what already
# exists (credit account + recorded credit payments) and lets the user
# override any of it. Nothing is written to the credit tables.
class DataCollectorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Credit User", email: "credit@example.com", password: "password123")
    @loan = create_loan(
      outstanding_balance: "112_400_000", interest_rate: "21.27", interest_rate_type: "effective_annual",
      installment_amount: "2_817_600", installment_count: 60, installments_paid: 12,
      start_date: Date.new(2025, 10, 5)
    )
  end

  test "collects the loan data from the credit account" do
    inputs = Credits::DataCollector.call(money_source: @loan)

    assert_equal BigDecimal("112400000"), inputs[:balance]
    assert_equal BigDecimal("21.27"), inputs[:interest_rate]
    assert_equal "effective_annual", inputs[:interest_rate_type]
    assert_equal "monthly", inputs[:payment_frequency]
    assert_equal BigDecimal("2817600"), inputs[:installment_amount]
    assert_equal 60, inputs[:installment_count]
    assert_equal 12, inputs[:current_installment_number]
    assert_equal Date.new(2025, 10, 5), inputs[:start_date]
    assert_empty inputs[:user_supplied]
  end

  test "defaults the payment frequency to monthly" do
    @loan.credit_account.update_column(:payment_frequency, nil)

    assert_equal "monthly", Credits::DataCollector.call(money_source: @loan)[:payment_frequency]
  end

  test "takes the latest payment components and date from recorded payments" do
    create_payment(Date.new(2026, 9, 5), principal: 1_050_000, interest: 1_450_000,
                                 insurance: 317_600, other: 0)

    inputs = Credits::DataCollector.call(money_source: @loan)

    assert_equal Date.new(2026, 9, 5), inputs[:latest_payment_date]
    assert_equal BigDecimal("1050000"), inputs[:latest_principal]
    assert_equal BigDecimal("1450000"), inputs[:latest_interest]
    assert_equal BigDecimal("317600"), inputs[:latest_insurance]
    assert_equal BigDecimal("0"), inputs[:latest_other]
  end

  test "derives the current installment number from installments_paid" do
    create_payment(Date.new(2026, 8, 5), principal: 1_000_000, interest: 1_400_000)
    create_payment(Date.new(2026, 9, 5), principal: 1_050_000, interest: 1_450_000)

    inputs = Credits::DataCollector.call(money_source: @loan)

    # 12 installments registered on the credit account plus the 2 just recorded.
    assert_equal 2, inputs[:actual_payments_count]
    assert_equal 14, inputs[:current_installment_number]
  end

  test "user overrides win and are recorded as user-supplied" do
    inputs = Credits::DataCollector.call(
      money_source: @loan,
      overrides: {
        "outstanding_balance" => "110000000",
        "interest_rate" => "22.5",
        "current_installment_number" => "20",
        "insurance_amount" => "300000",
        "latest_payment_date" => "2026-10-05"
      }
    )

    assert_equal BigDecimal("110000000"), inputs[:balance]
    assert_equal BigDecimal("22.5"), inputs[:interest_rate]
    assert_equal 20, inputs[:current_installment_number]
    assert_equal Date.new(2026, 10, 5), inputs[:latest_payment_date]
    assert_equal BigDecimal("300000"), inputs[:latest_insurance]
    assert_equal %w[balance current_installment_number interest_rate latest_insurance latest_payment_date].sort,
                 inputs[:user_supplied].sort
  end

  test "blank overrides are ignored" do
    inputs = Credits::DataCollector.call(money_source: @loan, overrides: { "interest_rate" => "" })

    assert_equal BigDecimal("21.27"), inputs[:interest_rate]
    assert_empty inputs[:user_supplied]
  end

  private

  def create_loan(outstanding_balance: nil, interest_rate: nil, interest_rate_type: nil,
                  installment_amount: nil, installment_count: nil, installments_paid: nil, start_date: nil)
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    loan.create_credit_account!(
      principal_amount: 200_000_000, outstanding_balance: outstanding_balance,
      interest_rate: interest_rate, interest_rate_type: interest_rate_type,
      installment_amount: installment_amount, installment_count: installment_count,
      installments_paid: installments_paid, start_date: start_date,
      payment_frequency: "monthly"
    )
    loan
  end

  def create_payment(date, principal: 0, interest: 0, insurance: 0, other: 0)
    total = principal + interest + insurance + other
    expense = Expense.create!(
      user: @user, amount: total, description: "Cuota hipoteca", date: date,
      kind: "expense", source: "manual", money_source: @loan
    )
    Payment.create!(
      user: @user, expense: expense, money_source: @loan, date: date, amount: total,
      principal_amount: principal, interest_amount: interest,
      insurance_amount: insurance, other_amount: other
    )
  end
end
