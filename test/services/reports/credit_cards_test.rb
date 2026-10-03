# frozen_string_literal: true

require "test_helper"

class ReportsCreditCardsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cards User", email: "reports_cards_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @visa = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @visa.create_credit_account!(credit_limit: 10_000_000, card_brand: "visa", card_last_four: "1234")
    @mastercard = @user.money_sources.create!(name: "Mastercard", kind: "credit_card", active: true)
    @mastercard.create_credit_account!(credit_limit: 8_000_000)
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def card_expense(amount, source: @visa, date: Date.new(2026, 9, 10))
    Expense.create!(user: @user, category: @food, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def report
    Reports::CreditCards.new(user: @user, filter: @filter).call
  end

  def card_row(name)
    report[:cards].find { |c| c[:name] == name }
  end

  test "reports limit, used, available and utilization per card" do
    @visa.update_column(:cached_balance, -3_200_000) # rubocop:disable Rails/SkipsModelValidations

    visa = card_row("Visa")

    assert_equal 10_000_000.to_d, visa[:limit]
    assert_equal 3_200_000.to_d, visa[:used]
    assert_equal 6_800_000.to_d, visa[:available]
    assert_in_delta 32.0, visa[:utilization_pct], 0.1
  end

  test "purchases are card expenses without attached payments" do
    card_expense(-2_100_000)

    assert_equal 2_100_000.to_d, card_row("Visa")[:purchases]
  end

  test "payments include payment records and transfers into the card" do
    card_expense = card_expense(-1_400_000)
    Payment.create!(user: @user, expense: card_expense, money_source: @visa, amount: 1_400_000,
                    principal_amount: 1_400_000)
    @user.transfers.create!(from_source: @bank, to_source: @visa, amount: 600_000,
                            date: Date.new(2026, 9, 20))

    assert_equal 2_000_000.to_d, card_row("Visa")[:payments]
  end

  test "interest and fees come from the payment distribution" do
    card_expense = card_expense(-1_400_000)
    Payment.create!(user: @user, expense: card_expense, money_source: @visa, amount: 1_400_000,
                    principal_amount: 1_200_000, interest_amount: 120_000,
                    insurance_amount: 30_000, other_amount: 50_000)

    visa = card_row("Visa")

    assert_equal 120_000.to_d, visa[:interest]
    assert_equal 80_000.to_d, visa[:fees]
    assert_equal 1_400_000.to_d, visa[:payments]
  end

  test "card expenses with attached payments are not purchases again" do
    card_expense = card_expense(-800_000)
    Payment.create!(user: @user, expense: card_expense, money_source: @visa, amount: 800_000,
                    principal_amount: 800_000)

    visa = card_row("Visa")

    assert_equal 0.to_d, visa[:purchases]
    assert_equal 800_000.to_d, visa[:payments]
  end

  test "loan payments are not attributed to the card" do
    installment = card_expense(-2_800_000, source: @bank)
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 2_800_000,
                    principal_amount: 2_800_000)

    visa = card_row("Visa")

    assert_equal 0.to_d, visa[:payments]
    assert_equal 0.to_d, visa[:purchases]
  end

  test "payment records are not counted as purchases of the paying card" do
    bank_expense = card_expense(-400_000, source: @bank)
    Payment.create!(user: @user, expense: bank_expense, money_source: @visa, amount: 400_000,
                    principal_amount: 400_000)

    report_data = report

    assert_equal 0.to_d, card_row("Davibank")&.dig(:purchases) || 0.to_d
    assert_equal 400_000.to_d, card_row("Visa")[:payments]
  end

  test "closing balance reflects current used credit, opening is nil without history" do
    @visa.update_column(:cached_balance, -1_000_000) # rubocop:disable Rails/SkipsModelValidations

    visa = card_row("Visa")

    assert_nil visa[:opening]
    assert_equal 1_000_000.to_d, visa[:closing]
  end

  test "consolidates totals across cards" do
    card_expense(-2_100_000)
    card_expense(-1_500_000, source: @mastercard)
    @visa.update_column(:cached_balance, -3_200_000) # rubocop:disable Rails/SkipsModelValidations
    @mastercard.update_column(:cached_balance, -1_500_000) # rubocop:disable Rails/SkipsModelValidations

    totals = report[:totals]

    assert_equal 18_000_000.to_d, totals[:limit]
    assert_equal 4_700_000.to_d, totals[:used]
    assert_equal 13_300_000.to_d, totals[:available]
    assert_in_delta 26.1, totals[:utilization_pct], 0.1
    assert_equal 3_600_000.to_d, totals[:purchases]
  end

  test "respects the credit card filter" do
    card_expense(-2_100_000)
    card_expense(-1_500_000, source: @mastercard)
    scoped_filter = Reports::Filter.new(user: @user, period: @period, credit_card_id: @visa.id)

    data = Reports::CreditCards.new(user: @user, filter: scoped_filter).call

    assert_equal 1, data[:cards].size
    assert_equal 2_100_000.to_d, data[:cards].first[:purchases]
  end

  test "empty period yields zeros and current balances" do
    @visa.update_column(:cached_balance, -500_000) # rubocop:disable Rails/SkipsModelValidations

    data = report

    assert_equal 2, data[:cards].size
    assert_equal 0.to_d, data[:cards].first[:purchases]
    assert_equal 0.to_d, data[:totals][:purchases]
  end

  test "card without a credit account shows zero limit and nil utilization" do
    @user.money_sources.create!(name: "Naked Card", kind: "credit_card", active: true)

    row = card_row("Naked Card")

    assert_nil row[:limit]
    assert_nil row[:available]
    assert_nil row[:utilization_pct]
  end
end
