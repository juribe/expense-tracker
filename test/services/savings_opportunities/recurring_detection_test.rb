# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesRecurringDetectionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Recurring User", email: "savings_recurring@example.com", password: "password123")
    @category = Category.create!(name: "Suscripciones de prueba", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    @date = Date.new(2026, 10, 15)
    @window = SavingsOpportunities::Window.new(user: @user, date: @date)
  end

  def expense(amount, description:, date:, category: @category)
    Expense.create!(user: @user, category: category, money_source: @bank, amount: amount,
                    date: date, description: description)
  end

  def report
    SavingsOpportunities::RecurringDetection.new(user: @user, window: @window).call
  end

  test "detects a monthly payment with consistent amount and dates as confirmed" do
    [ [ 7, 12 ], [ 8, 12 ], [ 9, 12 ], [ 10, 12 ] ].each do |month, day|
      expense(-29_900, description: "NETFLIX.COM", date: Date.new(2026, month, day))
    end

    row = report[:rows].first

    assert_equal "monthly", row[:frequency]
    assert_equal :confirmed, row[:confidence]
    assert_equal 29_900.to_d, row[:monthly_amount]
    assert_equal 4, row[:occurrences]
    assert_equal 29_900.to_d, report[:total_monthly]
  end

  test "detects weekly patterns" do
    [ 1, 8, 15, 22 ].each do |day|
      expense(-8_000, description: "Café Juan Valdez", date: Date.new(2026, 9, day))
    end

    row = report[:rows].first

    assert_equal "weekly", row[:frequency]
    assert_in_delta 34_667, row[:monthly_amount].to_f, 1.0
  end

  test "marks a payment as possible when the amount varies moderately" do
    expense(-20_000, description: "Gimnasio Bodytech", date: Date.new(2026, 7, 1))
    expense(-24_000, description: "Gimnasio Bodytech", date: Date.new(2026, 8, 3))
    expense(-22_000, description: "Gimnasio Bodytech", date: Date.new(2026, 9, 1))

    row = report[:rows].first

    assert_equal :possible, row[:confidence]
  end

  test "ignores casual matches with fewer than three occurrences" do
    expense(-50_000, description: "Ferretería El Tornillo", date: Date.new(2026, 8, 1))
    expense(-50_000, description: "Ferretería El Tornillo", date: Date.new(2026, 10, 1))

    assert_empty report[:rows]
  end

  test "ignores matches with wildly different amounts" do
    expense(-10_000, description: "Servicio Variable", date: Date.new(2026, 7, 1))
    expense(-40_000, description: "Servicio Variable", date: Date.new(2026, 8, 1))
    expense(-15_000, description: "Servicio Variable", date: Date.new(2026, 9, 1))

    assert_empty report[:rows]
  end

  test "normalizes merchant descriptions before grouping" do
    expense(-29_900, description: "Netflix 1234", date: Date.new(2026, 7, 12))
    expense(-29_900, description: "NETFLIX.COM", date: Date.new(2026, 8, 12))
    expense(-29_900, description: "netflix 12/09", date: Date.new(2026, 9, 12))

    rows = report[:rows]

    assert_equal 1, rows.size
    assert_equal 3, rows.first[:occurrences]
  end

  test "includes detected movements and does not mark a payment as dispensable" do
    [ 7, 8, 9, 10 ].each do |month|
      expense(-29_900, description: "Spotify", date: Date.new(2026, month, 10))
    end

    row = report[:rows].first

    assert_equal 4, row[:movements].size
    assert row[:movements].first[:date].present?
    refute row.key?(:dispensable)
  end

  test "excludes debt payments" do
    loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    [ 7, 8, 9, 10 ].each do |month|
      installment = expense(-500_000, description: "Cuota crédito", date: Date.new(2026, month, 5))
      Payment.create!(user: @user, expense: installment, money_source: loan, amount: 500_000,
                      principal_amount: 500_000)
    end

    assert_empty report[:rows]
  end

  test "does not treat GMF bank charges as recurring payments" do
    [ 7, 8, 9, 10 ].each do |month|
      Expense.create!(user: @user, category: @category, money_source: @bank, amount: -1_200,
                      date: Date.new(2026, month, 12), description: "GMF 4x1.000 (Gasto)",
                      source: "gmf", gmf_origin_type: "Expense", gmf_origin_id: SecureRandom.uuid)
    end

    assert_empty report[:rows]
  end

  test "scopes detection to the user" do
    other = User.create!(name: "Other", email: "savings_recurring_other@example.com", password: "password123")
    other_bank = other.money_sources.create!(name: "Other", kind: "account", active: true,
                                             starting_balance: 1_000_000_000)
    [ 7, 8, 9, 10 ].each do |month|
      Expense.create!(user: other, category: @category, money_source: other_bank, amount: -29_900,
                      date: Date.new(2026, month, 12), description: "Netflix")
    end

    assert_empty report[:rows]
  end
end
