# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesSimulatorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Sim User", email: "savings_sim@example.com", password: "password123")
    @food = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    @fun = Category.create!(name: "Entretenimiento", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    @date = Date.new(2026, 10, 15)
    @window = SavingsOpportunities::Window.new(user: @user, date: @date)
  end

  def expense(amount, category:, date: Date.new(2026, 10, 5))
    Expense.create!(user: @user, category: category, money_source: @bank, amount: amount,
                    date: date, description: "x")
  end

  def rows
    SavingsOpportunities::CategoryAnalysis.new(user: @user, window: @window).call[:all_rows]
  end

  test "builds a real spending base per category without duplicating rows" do
    expense(-850_000, category: @food)
    expense(-300_000, category: @fun)

    data = SavingsOpportunities::Simulator.new(window: @window, categories: rows).call

    assert_equal 2, data[:rows].size
    assert_equal %w[Restaurantes Entretenimiento], data[:rows].map { |row| row[:name] }
    assert_equal [ 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50,
                  55, 60, 65, 70, 75, 80, 85, 90, 95, 100 ], data[:percentages]
  end

  test "precomputes every allowed reduction from the user's real spending" do
    expense(-850_000, category: @food)

    row = SavingsOpportunities::Simulator.new(window: @window, categories: rows).call[:rows].first

    assert_equal 850_000.to_d, row[:current]
    assert_equal 42_500, row[:steps][5]
    assert_equal 85_000, row[:steps][10]
    assert_equal 127_500, row[:steps][15]
  end

  test "computes scenario totals with backend money rules" do
    expense(-850_000, category: @food)
    expense(-300_000, category: @fun)
    simulator_rows = SavingsOpportunities::Simulator.new(window: @window, categories: rows).call[:rows]
    reductions = {
      simulator_rows.find { |row| row[:name] == "Restaurantes" }[:id] => "15",
      simulator_rows.find { |row| row[:name] == "Entretenimiento" }[:id] => "10"
    }

    total = SavingsOpportunities::Simulator.total(rows: simulator_rows, reductions: reductions)

    assert_equal 157_500.to_d, total
  end

  test "clamps negative and above 100 percentages" do
    expense(-850_000, category: @food)
    simulator_rows = SavingsOpportunities::Simulator.new(window: @window, categories: rows).call[:rows]
    id = simulator_rows.first[:id]

    assert_equal 0.to_d, SavingsOpportunities::Simulator.total(rows: simulator_rows, reductions: { id => "-20" })
    assert_equal 850_000.to_d, SavingsOpportunities::Simulator.total(rows: simulator_rows, reductions: { id => "180" })
  end

  test "ignores unknown categories and empty reductions" do
    expense(-850_000, category: @food)
    simulator_rows = SavingsOpportunities::Simulator.new(window: @window, categories: rows).call[:rows]

    assert_equal 0.to_d, SavingsOpportunities::Simulator.total(rows: simulator_rows, reductions: { "unknown" => "50" })
    assert_equal 0.to_d, SavingsOpportunities::Simulator.total(rows: simulator_rows, reductions: {})
  end

  test "snaps a custom savings rate to the slider steps" do
    @food.update!(suggested_savings_percentage: 12)
    expense(-850_000, category: @food)

    row = SavingsOpportunities::Simulator.new(window: @window, categories: rows).call[:rows].first

    assert_equal 10, row[:default_percentage]
    assert_equal 85_000, row[:steps][row[:default_percentage]]
  end

  test "never offers more than five categories" do
    categories = 6.times.map do |i|
      category = Category.create!(name: "Cat #{i}", is_default: true, category_type: "expense")
      expense(-100_000 * (i + 1), category: category)
      category
    end

    analysis_rows = SavingsOpportunities::CategoryAnalysis.new(user: @user, window: @window).call[:all_rows]
    data = SavingsOpportunities::Simulator.new(window: @window, categories: analysis_rows).call

    assert_equal 5, data[:rows].size
    assert_equal categories.last.name, data[:rows].first[:name]
  end
end
