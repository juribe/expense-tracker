# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesSmallExpensesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Small User", email: "savings_small@example.com", password: "password123")
    @food = Category.create!(name: "Café y snacks", is_default: true, category_type: "expense")
    @home = Category.create!(name: "Hogar", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    @date = Date.new(2026, 10, 15)
    @window = SavingsOpportunities::Window.new(user: @user, date: @date)
  end

  def expense(amount, description:, date: Date.new(2026, 10, 5), category: @food)
    Expense.create!(user: @user, category: category, money_source: @bank, amount: amount,
                    date: date, description: description)
  end

  def report
    SavingsOpportunities::SmallExpenses.new(user: @user, window: @window).call
  end

  test "groups frequent low value purchases and reports the accumulated total" do
    12.times { |i| expense(-8_000, description: "Café", date: Date.new(2026, 10, (i % 12) + 1)) }
    10.times { |i| expense(-7_000, description: "Snack", date: Date.new(2026, 10, (i % 10) + 1)) }
    expense(-1_500_000, description: "Arriendo", category: @home)

    data = report
    names = data[:groups].map { |group| group[:name] }

    assert data[:available]
    assert_equal 22, data[:count]
    assert_equal 166_000.to_d, data[:total]
    assert_includes names, "Café"
    assert_includes names, "Snack"
    assert_equal 12, data[:groups].find { |group| group[:name] == "Café" }[:count]
  end

  test "computes an adaptive threshold from the user's own transactions" do
    6.times { |i| expense(-50_000, description: "Café premium", date: Date.new(2026, 10, i + 1)) }
    6.times { |i| expense(-700_000, description: "Restaurante", date: Date.new(2026, 10, i + 1)) }

    assert_equal 50_000.to_d, report[:threshold]
  end

  test "ignores tiny one-off charges when choosing the adaptive threshold" do
    14.times { |i| expense(-1_000, description: "Pago #{i}", date: Date.new(2026, 10, (i % 14) + 1)) }
    [ 15_120, 18_100, 41_500, 45_750, 60_800 ].each_with_index do |amount, i|
      expense(-amount, description: "DiDi CO Food", date: Date.new(2026, 10, i + 1))
    end
    expense(-400_000, description: "Entrenador Gym")

    data = report

    assert data[:available]
    assert_equal 60_800.to_d, data[:threshold]
    assert_equal 5, data[:count]
    assert_equal 181_270.to_d, data[:total]
    assert_equal "DiDi CO Food", data[:groups].first[:name]
  end

  test "includes the average amount per movement and the category distribution" do
    5.times { |i| expense(-8_000, description: "Café", date: Date.new(2026, 10, i + 1)) }
    5.times { |i| expense(-30_000, description: "Restaurante", date: Date.new(2026, 10, i + 1)) }

    data = report

    assert_equal 8_000.to_d, data[:average]
    assert_equal 1, data[:by_category].size
    assert_equal 40_000.to_d, data[:by_category].first[:total]
  end

  test "is unavailable when there are not enough movements" do
    expense(-8_000, description: "Café")
    expense(-12_000, description: "Panadería")

    refute report[:available]
  end

  test "excludes transactions above the adaptive threshold" do
    5.times { |i| expense(-8_000, description: "Café", date: Date.new(2026, 10, i + 1)) }
    expense(-900_000, description: "Mercado grande")

    names = report[:groups].map { |group| group[:name] }

    assert_includes names, "Café"
    refute_includes names, "Mercado grande"
  end

  test "does not include one-off purchases as recurring small expenses" do
    5.times { |i| expense(-8_000, description: "Café", date: Date.new(2026, 10, i + 1)) }
    expense(-9_000, description: "Compra única")
    expense(-900_000, description: "Mercado grande")

    names = report[:groups].map { |group| group[:name] }

    assert_includes names, "Café"
    refute_includes names, "Compra única"
  end

  test "exposes the related movements per group" do
    5.times { |i| expense(-8_000, description: "Café", date: Date.new(2026, 10, i + 1)) }
    expense(-900_000, description: "Mercado grande")

    group = report[:groups].first

    assert_equal 5, group[:movements].size
    assert_equal Date.new(2026, 10, 5), group[:movements].first[:date]
  end

  test "does not count GMF bank charges as small purchases" do
    6.times do |i|
      Expense.create!(user: @user, category: @food, money_source: @bank, amount: -1_200,
                      date: Date.new(2026, 10, i + 1), description: "GMF 4x1.000",
                      source: "gmf", gmf_origin_type: "Expense", gmf_origin_id: SecureRandom.uuid)
    end
    5.times { |i| expense(-8_000, description: "Café", date: Date.new(2026, 10, i + 1)) }
    expense(-900_000, description: "Mercado grande")

    data = report

    assert_equal 40_000.to_d, data[:total]
    refute_includes data[:groups].map { |group| group[:name] }, "GMF 4x1.000"
  end

  test "is scoped to the user" do
    other = User.create!(name: "Other", email: "savings_small_other@example.com", password: "password123")
    other_bank = other.money_sources.create!(name: "Other", kind: "account", active: true,
                                             starting_balance: 1_000_000_000)
    6.times do |i|
      Expense.create!(user: other, category: @food, money_source: other_bank, amount: -8_000,
                      date: Date.new(2026, 10, i + 1), description: "Café")
    end

    refute report[:available]
  end
end
