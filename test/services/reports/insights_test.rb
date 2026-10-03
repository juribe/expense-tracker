# frozen_string_literal: true

require "test_helper"

class ReportsInsightsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Insights User", email: "reports_insights_test@example.com", password: "password123")
    @food = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @card.create_credit_account!(credit_limit: 10_000_000)
    @loan = @user.money_sources.create!(name: "Rotativo", kind: "loan", active: true)
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def expense(amount, date:, category: @food, source: @bank)
    Expense.create!(user: @user, category: category, money_source: source, amount: amount,
                    date: date, description: "x")
  end

  def insights
    Reports::Insights.new(user: @user, filter: @filter).call
  end

  def category_spike(september, august, previous_months: [])
    expense(-september.to_d, date: Date.new(2026, 9, 10))
    expense(-august.to_d, date: Date.new(2026, 8, 10))
    previous_months.each_with_index do |amount, index|
      expense(-amount.to_d, date: Date.new(2026, 8, 10) - (index + 1).months)
    end
  end

  test "insight when a category rises sharply versus the previous month" do
    category_spike(1_000_000, 700_000)

    data = insights
    insight = data.find { |i| i[:rule] == :category_previous_period_increase }

    assert insight
    assert insight[:message].include?("Restaurantes")
    assert insight[:message].include?("43") # 43% increase
    assert_equal @food.id, insight[:category_id]
    assert_equal 43, insight[:data][:delta_pct]
  end

  test "no insight when the rise is below the threshold" do
    category_spike(1_050_000, 1_000_000) # +5%

    assert_empty insights
  end

  test "insight when a category is unusually high versus the 6-month average" do
    expense(-2_000_000, date: Date.new(2026, 9, 10))
    [ 1_000_000, 900_000, 1_100_000, 950_000, 1_050_000, 1_000_000 ].each_with_index do |amount, index|
      expense(-amount.to_d, date: Date.new(2026, 8, 10) - index.months)
    end

    data = insights
    insight = data.find { |i| i[:rule] == :category_unusual_average }

    assert insight
    assert insight[:message].include?("Restaurantes")
    assert insight[:data][:ratio] > 1.5
  end

  test "insight when total spending rises sharply versus previous period" do
    expense(-5_000_000, date: Date.new(2026, 9, 10), category: @food)
    expense(-1_000_000, date: Date.new(2026, 9, 12), category: @transport)
    expense(-3_000_000, date: Date.new(2026, 8, 10), category: @food)
    expense(-1_000_000, date: Date.new(2026, 8, 12), category: @transport)

    assert insights.any? { |i| i[:rule] == :spending_increase }
  end

  test "insight when a single transaction is a large outlier" do
    expense(-8_000_000, date: Date.new(2026, 9, 10), category: @food)
    expense(-500_000, date: Date.new(2026, 9, 11), category: @food)
    expense(-400_000, date: Date.new(2026, 9, 12), category: @food)
    expense(-600_000, date: Date.new(2026, 9, 13), category: @food)
    expense(-300_000, date: Date.new(2026, 9, 14), category: @food)

    assert insights.any? { |i| i[:rule] == :large_transaction }
  end

  test "insight when an unusual number of transactions occurs" do
    30.times do |index|
      expense(-50_000, date: Date.new(2026, 9, (index % 15) + 1), category: @food)
    end
    6.times { |index| expense(-10_000, date: Date.new(2026, 8, index + 1), category: @food) }
    6.times { |index| expense(-10_000, date: Date.new(2026, 7, index + 1), category: @food) }
    6.times { |index| expense(-10_000, date: Date.new(2026, 6, index + 1), category: @food) }
    6.times { |index| expense(-10_000, date: Date.new(2026, 5, index + 1), category: @food) }

    assert insights.any? { |i| i[:rule] == :transaction_count_unusual }
  end

  test "insight when credit usage is high and payments do not cover purchases" do
    # Usage: 60% of the limit, with purchases outpacing payments this period.
    @card.update_column(:cached_balance, -6_000_000) # rubocop:disable Rails/SkipsModelValidations
    expense(-2_000_000, date: Date.new(2026, 9, 10), source: @card)
    payment_expense = expense(-500_000, date: Date.new(2026, 9, 12))
    Payment.create!(user: @user, expense: payment_expense, money_source: @card, amount: 500_000,
                    principal_amount: 500_000)

    assert insights.any? { |i| i[:rule] == :credit_utilization_increase }
  end

  test "insight when recurring commitments grow" do
    expense(-100_000, date: Date.new(2026, 9, 10))
    expense(-1_000, date: Date.new(2026, 8, 10))
    RecurringTemplate.create!(user: @user, category: @food, kind: "expense", amount: 1_500_000,
                              frequency: "monthly", payment_day: 5, active: true, description: "Rent")

    assert insights.any? { |i| i[:rule] == :recurring_commitment_increase }
  end

  test "insight when debt payments rise sharply" do
    installment = expense(-4_000_000, date: Date.new(2026, 9, 10))
    Payment.create!(user: @user, expense: installment, money_source: @loan, amount: 4_000_000,
                    principal_amount: 4_000_000)
    old_installment = expense(-2_000_000, date: Date.new(2026, 8, 10))
    Payment.create!(user: @user, expense: old_installment, money_source: @loan, amount: 2_000_000,
                    principal_amount: 2_000_000)

    assert insights.any? { |i| i[:rule] == :debt_payment_increase }
  end

  test "no insights without meaningful data" do
    assert_empty insights
  end

  test "insights are capped and always carry structure" do
    category_spike(1_000_000, 700_000)
    expense(-5_000_000, date: Date.new(2026, 9, 10), category: @food)
    expense(-500_000, date: Date.new(2026, 9, 11), category: @food)
    expense(-400_000, date: Date.new(2026, 9, 12), category: @food)
    expense(-600_000, date: Date.new(2026, 9, 13), category: @food)
    expense(-300_000, date: Date.new(2026, 9, 14), category: @food)

    data = insights

    assert data.size <= Reports::Thresholds::MAX_INSIGHTS
    data.each do |insight|
      assert insight[:rule]
      assert insight[:message].present?
      assert insight[:kind].in?(%w[increase decrease anomaly])
    end
  end

  test "no insights with an empty period" do
    empty_filter = Reports::Filter.new(user: @user, period: Reports::Period.new(preset: "last_month", date: Date.new(2026, 9, 15)))

    assert_empty Reports::Insights.new(user: @user, filter: empty_filter).call
  end
end
