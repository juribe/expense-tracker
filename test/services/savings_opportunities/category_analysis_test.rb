# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesCategoryAnalysisTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Savings User", email: "savings_category@example.com", password: "password123")
    @food = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    @home = Category.create!(name: "Hogar", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    @date = Date.new(2026, 10, 15)
    @window = SavingsOpportunities::Window.new(user: @user, date: @date)
  end

  def expense(amount, category: @food, date: Date.new(2026, 10, 5), user: @user, source: @bank)
    Expense.create!(user: user, category: category, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def report
    SavingsOpportunities::CategoryAnalysis.new(user: @user, window: @window).call
  end

  test "compares current spending against the average of complete previous months" do
    expense(-600_000, date: Date.new(2026, 7, 5))
    expense(-600_000, date: Date.new(2026, 8, 5))
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-300_000, date: Date.new(2026, 9, 25))
    expense(-900_000, date: Date.new(2026, 10, 5))

    row = report[:all_rows].first

    assert_equal 900_000.to_d, row[:current]
    assert_equal 700_000.to_d, row[:previous_average]
    assert_equal 600_000.to_d, row[:comparable_average]
    assert_in_delta 50.0, row[:delta_pct], 0.1
  end

  test "uses equivalent elapsed days instead of a full incomplete month" do
    expense(-600_000, date: Date.new(2026, 7, 5))
    expense(-600_000, date: Date.new(2026, 8, 5))
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-900_000, date: Date.new(2026, 9, 25))
    expense(-600_000, date: Date.new(2026, 10, 5))

    row = report[:all_rows].first

    assert_equal 600_000.to_d, row[:comparable_average]
    assert_in_delta 0.0, row[:delta_pct], 0.1
  end

  test "adds the configured savings rate to the estimated reduction" do
    @food.update!(suggested_savings_percentage: 15)
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-600_000, date: Date.new(2026, 10, 5))

    row = report[:opportunities].first

    assert_equal 15.to_d, row[:suggested_percentage]
    assert_equal 90_000.to_d, row[:potential]
  end

  test "detects a significant category even without an increase" do
    expense(-300_000, category: @home, date: Date.new(2026, 10, 2))
    expense(-700_000, category: @food, date: Date.new(2026, 9, 5))
    expense(-700_000, category: @food, date: Date.new(2026, 10, 5))

    rows = report[:opportunities]

    assert_includes rows.map { |row| row[:name] }, "Hogar"
  end

  test "does not flag small categories with no relevant variation" do
    [ 7, 8, 9 ].each { |month| expense(-990_000, category: @food, date: Date.new(2026, month, 5)) }
    expense(-990_000, category: @food, date: Date.new(2026, 10, 5))
    [ 7, 8, 9 ].each { |month| expense(-10_000, category: @home, date: Date.new(2026, month, 5)) }
    expense(-10_000, category: @home, date: Date.new(2026, 10, 5))

    names = report[:opportunities].map { |row| row[:name] }

    refute_includes names, "Hogar"
  end

  test "marks comparison unavailable when there is no complete prior history" do
    expense(-900_000, date: Date.new(2026, 10, 5))

    data = report

    refute data[:comparison_available]
    assert_empty data[:opportunities]
    assert_equal 900_000.to_d, data[:total]
  end

  test "excludes debt payments from consumption spending" do
    loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    installment = expense(-900_000, date: Date.new(2026, 10, 5))
    Payment.create!(user: @user, expense: installment, money_source: loan, amount: 900_000,
                    principal_amount: 900_000)
    expense(-100_000, date: Date.new(2026, 9, 5))

    assert_equal 0.to_d, report[:total]
    assert_empty report[:all_rows]
  end

  test "scopes every calculation to the user" do
    other = User.create!(name: "Other", email: "savings_category_other@example.com", password: "password123")
    other_bank = other.money_sources.create!(name: "Other Bank", kind: "account", active: true,
                                             starting_balance: 1_000_000_000)
    expense(-600_000, date: Date.new(2026, 9, 5))
    expense(-900_000, date: Date.new(2026, 10, 5))
    expense(-5_000_000, date: Date.new(2026, 10, 5), user: other, source: other_bank)

    assert_equal 900_000.to_d, report[:total]
  end

  test "keeps decimal precision for large amounts" do
    expense(-99_999_999.99, date: Date.new(2026, 9, 5))
    expense(-99_999_999.99, date: Date.new(2026, 10, 5))

    assert_equal 99_999_999.99.to_d, report[:all_rows].first[:current]
  end

  test "excludes GMF bank charges from the savings analysis" do
    expense(-500_000, date: Date.new(2026, 9, 5))
    expense(-600_000, date: Date.new(2026, 10, 5))
    Expense.create!(user: @user, category: @food, money_source: @bank, amount: -4_000_000,
                    date: Date.new(2026, 10, 6), description: "GMF 4x1.000",
                    source: "gmf", gmf_origin_type: "Expense", gmf_origin_id: SecureRandom.uuid)

    data = report

    assert_equal 600_000.to_d, data[:total]
    refute_includes data[:all_rows].map { |row| row[:name] }, "4x1.000 (GMF)"
  end

  test "builds a monthly series with the current period last" do
    expense(-100_000, date: Date.new(2026, 9, 5))
    expense(-200_000, date: Date.new(2026, 10, 5))

    months = report[:all_rows].first[:months]

    assert_equal 3, months.size
    assert months.last[:current]
    assert_equal 200_000.to_d, months.last[:total]
  end
end
