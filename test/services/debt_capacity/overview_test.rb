# frozen_string_literal: true

require "test_helper"

class DebtCapacityOverviewTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Debt Overview User", email: "debt_overview_test@example.com", password: "password123")
    @income_category = Category.create!(name: "Salario", category_type: "income", is_default: true)
    @expense_category = Category.create!(name: "Vivienda", category_type: "expense", is_default: true)
    @month = Date.new(2026, 9, 15)
  end

  test "consolidates active cards, revolving credits and amortizing loans once each" do
    card = create_card(name: "Visa", limit: 8_000_000, used: 2_500_000, installment: 350_000)
    revolving = create_loan(name: "Rotativo", sub_kind: "revolving", balance: 1_200_000, installment: 180_000)
    mortgage = create_loan(name: "Hipotecario", sub_kind: "mortgage", balance: 80_000_000, installment: 1_500_000)
    @user.money_sources.create!(name: "Cuenta", kind: "account", active: true)

    debts = overview[:debts]

    assert_equal [ card.id, revolving.id, mortgage.id ].sort, debts.map { |debt| debt[:id] }.sort
    assert_equal 83_700_000.to_d, overview[:summary][:total_debt]
    assert_equal 2_030_000.to_d, overview[:summary][:monthly_installments]
  end

  test "exposes card limit, used credit, available credit and monthly commitment" do
    card = create_card(name: "Mastercard", limit: 5_000_000, used: 3_000_000, installment: 250_000)

    debt = overview[:debts].find { |row| row[:id] == card.id }

    assert_equal 5_000_000.to_d, debt[:credit_limit]
    assert_equal 3_000_000.to_d, debt[:used_credit]
    assert_equal 2_000_000.to_d, debt[:available_credit]
    assert_equal 250_000.to_d, debt[:monthly_installment]
  end

  test "uses the revolving outstanding balance instead of its cash balance" do
    revolving = create_loan(name: "Cupo Rotativo", sub_kind: "revolving", balance: 1_750_000, installment: 200_000)
    revolving.update_column(:cached_balance, 0) # rubocop:disable Rails/SkipsModelValidations

    debt = overview[:debts].find { |row| row[:id] == revolving.id }

    assert_equal 1_750_000.to_d, debt[:balance]
  end

  test "does not include inactive debt sources" do
    create_card(name: "Tarjeta activa", limit: 5_000_000, used: 1_000_000)
    inactive = create_loan(name: "Crédito cerrado", sub_kind: "personal", balance: 4_000_000)
    inactive.update!(active: false)

    assert_equal [ "Tarjeta activa" ], overview[:debts].map { |debt| debt[:name] }
  end

  test "marks interest and installment values unavailable when source data is incomplete" do
    loan = @user.money_sources.create!(name: "Crédito sin datos", kind: "loan", active: true)
    loan.create_credit_account!

    debt = overview[:debts].find { |row| row[:id] == loan.id }

    assert_nil debt[:monthly_interest]
    assert_nil debt[:monthly_installment]
  end

  test "uses active recurring income as the monthly salary reference" do
    @user.recurring_templates.create!(
      category: @income_category, amount: 8_200_000, kind: "income", frequency: "monthly", source: "manual", active: true
    )
    @user.incomes.create!(amount: 12_000_000, date: @month, category: @income_category)

    assert_equal 8_200_000.to_d, overview[:summary][:monthly_income]
  end

  private

  def overview
    DebtCapacity::Overview.new(user: @user, month: @month).call
  end

  def create_card(name:, limit:, used:, installment: nil)
    card = @user.money_sources.create!(name: name, kind: "credit_card", active: true)
    card.create_credit_account!(credit_limit: limit, installment_amount: installment, interest_rate: 24.0,
                                interest_rate_type: "effective_annual")
    card.update_column(:cached_balance, -used) # rubocop:disable Rails/SkipsModelValidations
    card
  end

  def create_loan(name:, sub_kind:, balance:, installment: nil)
    loan = @user.money_sources.create!(name: name, kind: "loan", sub_kind: sub_kind, active: true)
    loan.create_credit_account!(outstanding_balance: balance, installment_amount: installment,
                                interest_rate: 12.0, interest_rate_type: "effective_annual")
    loan
  end
end
