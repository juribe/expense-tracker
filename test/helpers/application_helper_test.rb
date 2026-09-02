# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "available_credit_for subtracts debt from the credit limit" do
    assert_equal 9000000, available_credit_for({ "credit_limit" => "10000000", "balance" => "1000000" })
  end

  test "available_credit_for floors at zero" do
    assert_equal 0, available_credit_for({ "credit_limit" => "500000", "balance" => "2000000" })
  end

  test "available_credit_for returns zero without a credit limit" do
    assert_equal 0, available_credit_for({ "balance" => "100000" })
  end

  test "money_field_value renders Colombian number format" do
    assert_equal "67.429.112,92", money_field_value(67429112.92)
    assert_equal "5.734.980", money_field_value("5734980")
    assert_equal "", money_field_value(nil)
  end

  setup do
    @user = User.create!(name: "Test User", email: "app_helper_loans@example.com", password: "password123")
    @loan = @user.money_sources.create!(name: "Crédito Hipotecario en Pesos", kind: "loan", bank: "Davibank", active: true)
    @loan.build_credit_account(
      principal_amount: 170900000, outstanding_balance: 66959723, installment_amount: 1130642,
      installment_count: 192, installments_paid: 75, interest_rate: 18.05,
      interest_rate_type: "effective_annual", payment_frequency: "monthly", start_date: Date.new(2020, 1, 15)
    )
    @loan.save!
  end

  test "loan_identity picks the accent and icon by loan type" do
    assert_equal({ icon: "house", accent: "accent-purple" }, loan_identity(@loan))
    assert_equal({ icon: "arrow-repeat", accent: "accent-teal" },
                 loan_identity(@user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", starting_balance: 0)))
    assert_equal({ icon: "car-front", accent: "accent-amber" },
                 loan_identity(@user.money_sources.create!(name: "Crédito de Vehículo", kind: "loan", starting_balance: 0)))
  end

  test "loan_summary aggregates outstanding balance, active count, remaining and monthly payments" do
    second = @user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", starting_balance: 0, active: true)
    second.build_credit_account(principal_amount: 53049762, outstanding_balance: 53900000,
                                installment_amount: 1145600, installment_count: 48, installments_paid: 18)
    second.save!

    summary = loan_summary(@user.money_sources.where(kind: "loan").to_a)
    assert_equal BigDecimal("120859723"), summary[:total_balance]
    assert_equal 2, summary[:active_count]
    assert_equal BigDecimal("2276242"), summary[:next_30d]
    assert summary[:remaining].positive?
  end

  test "loan_summary is safe with loans that have no credit account" do
    bare = @user.money_sources.create!(name: "Préstamo", kind: "loan", starting_balance: 0, active: true)
    summary = loan_summary([ bare ])
    assert_equal 0, summary[:total_balance]
    assert_equal 1, summary[:active_count]
    assert_equal 0, summary[:remaining]
    assert_equal 0, summary[:next_30d]
  end

  test "next_payment_date prefers a scheduled recurring template payment day" do
    templ = @user.recurring_templates.create!(
      category: Category.create!(name: "Cuotas", is_default: true),
      kind: "expense", amount: 1000, frequency: "monthly", source: "wizard",
      money_source: @loan, payment_day: 20
    )
    date = next_payment_date(@loan)
    assert_kind_of Date, date
    assert_equal 20, date.day
  end

  test "next_payment_date falls back to deriving from start date and frequency" do
    @loan.recurring_templates.destroy_all
    date = next_payment_date(@loan)
    assert_kind_of Date, date
  end
end
