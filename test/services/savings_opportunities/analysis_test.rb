# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesAnalysisTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Analysis User", email: "savings_analysis@example.com", password: "password123")
    @food = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    @fun = Category.create!(name: "Entretenimiento", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    @date = Date.new(2026, 10, 15)
  end

  def expense(amount, category: @food, date: Date.new(2026, 10, 5), description: "x")
    Expense.create!(user: @user, category: category, money_source: @bank, amount: amount,
                    date: date, description: description)
  end

  def analysis
    SavingsOpportunities::Analysis.new(user: @user, date: @date).call
  end

  test "returns the empty state when the user has no expenses" do
    assert_equal :empty, analysis[:state]
    assert_equal 0.to_d, analysis[:totals][:potential_monthly]
  end

  test "returns the insufficient history state with only current period movements" do
    expense(-900_000)
    expense(-200_000, category: @fun)

    data = analysis

    assert_equal :insufficient_history, data[:state]
    refute data[:categories][:comparison_available]
  end

  test "uses the configured recurring payments when there is no previous-cycle history" do
    expense(-900_000)
    RecurringTemplate.create!(user: @user, category: @food, kind: "expense", description: "Netflix",
                              amount: 29_900, frequency: "monthly", source: "manual", payment_day: 12)

    data = analysis

    assert_equal :insufficient_history, data[:state]
    assert_equal "configured", data[:recurring][:source]
    assert_equal [ "Netflix" ], data[:recurring][:rows].map { |row| row[:name] }
    assert_equal 29_900.to_d, data[:recurring][:total_monthly]
    assert_equal 1, data[:totals][:configured_recurring_count]
    assert_equal 1, data[:totals][:opportunities_count]
    assert_equal 0.to_d, data[:totals][:potential_monthly]
  end

  test "does not use configured recurring payments when there is previous-cycle history" do
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-900_000)
    RecurringTemplate.create!(user: @user, category: @food, kind: "expense", description: "Netflix",
                              amount: 29_900, frequency: "monthly", source: "manual", payment_day: 12)

    data = analysis

    assert_equal :ok, data[:state]
    assert_equal "movements", data[:recurring][:source]
    assert_empty data[:recurring][:rows]
    assert_equal 0, data[:totals][:configured_recurring_count]
  end

  test "returns the ok state with complete history" do
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-900_000)
    expense(-300_000, category: @fun)

    assert_equal :ok, analysis[:state]
  end

  test "keeps recurring and small expenses out of the potential savings total" do
    [ 7, 8, 9 ].each { |month| expense(-600_000, date: Date.new(2026, month, 5)) }
    expense(-900_000)
    [ 7, 8, 9, 10 ].each { |month| expense(-29_900, date: Date.new(2026, month, 12), description: "Netflix") }

    data = analysis

    category_potential = data[:totals][:potential_monthly]
    assert_equal data[:categories][:opportunities].sum { |row| row[:potential] }, category_potential
    refute_equal 0.to_d, data[:recurring][:total_monthly]
  end

  test "never counts the same category twice" do
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-900_000)

    ids = analysis[:simulator][:rows].map { |row| row[:id] }

    assert_equal ids.uniq, ids
  end

  test "includes a stable fingerprint and generation timestamp" do
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-900_000)

    data = analysis

    assert data[:fingerprint].present?
    assert data[:generated_at].present?
    assert_equal @user.id, data[:user_id]
  end

  test "builds the AI-ready summary totals" do
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-900_000)
    expense(-300_000, category: @fun)

    totals = analysis[:totals]

    assert totals[:opportunities_count] >= 1
    assert_equal totals[:categories_count], analysis[:categories][:opportunities].size
  end
end
