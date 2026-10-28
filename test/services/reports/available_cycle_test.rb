# frozen_string_literal: true

require "test_helper"

class ReportsAvailableCycleTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Available Cycle", email: "available_cycle_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true, starting_balance: 8_000_000)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true, starting_balance: 0)
    @pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", active: true, starting_balance: 1_000_000)
    @card = @user.money_sources.create!(name: "Tarjeta", kind: "credit_card", active: true)
    @other = User.create!(name: "Other", email: "available_cycle_other@example.com", password: "password123")
  end

  def template(name:, amount:, payment_day: 10, active: true, user: @user)
    source = user == @user ? @bank : user.money_sources.create!(name: "Bank", kind: "account", active: true, starting_balance: 0)
    RecurringTemplate.create!(user: user, category: @food, kind: "expense", amount: amount,
                              frequency: "monthly", payment_day: payment_day, active: active,
                              description: name, money_source: source)
  end

  def report
    travel_to Date.new(2026, 10, 28) do
      Reports::AvailableCycle.new(user: @user).call
    end
  end

  test "current money includes accounts and cash but excludes pockets cards loans" do
    data = report
    assert_equal 8_000_000.to_d, data[:current_money]
  end

  test "pending expense without payments" do
    template(name: "Internet", amount: 100_000, payment_day: 28)
    data = report
    assert_equal 1, data[:pending_expenses].size
    assert_equal 100_000.to_d, data[:pending_expenses].first[:missing]
    assert_equal 100_000.to_d, data[:pending_total]
  end

  test "partial payment reduces pending" do
    t = template(name: "Internet", amount: 100_000, payment_day: 28)
    cycle = PayCycle.current(@user)
    RecurringTemplateProcessor.call(recurring_template: t, amount: 40_000, date: Date.new(2026, 10, 28), money_source: @bank, mark_as_paid: false)
    data = report
    assert_equal 60_000.to_d, data[:pending_expenses].first[:missing]
    assert_equal 60_000.to_d, data[:pending_total]
  end

  test "fully paid expense is excluded" do
    t = template(name: "Internet", amount: 100_000, payment_day: 28)
    RecurringTemplateProcessor.call(recurring_template: t, amount: 100_000, date: Date.new(2026, 10, 28), money_source: @bank, mark_as_paid: true)
    data = report
    assert_empty data[:pending_expenses]
    assert_equal 0.to_d, data[:pending_total]
  end

  test "remaining calculation positive zero negative" do
    template(name: "Internet", amount: 100_000, payment_day: 28)
    data = report
    assert_equal 7_900_000.to_d, data[:remaining]

    # negative scenario
    @bank.update!(starting_balance: 50_000)
    @bank.update!(cached_balance: 50_000)
    data2 = travel_to(Date.new(2026, 10, 28)) { Reports::AvailableCycle.new(user: @user).call }
    assert_equal (-50_000).to_d, data2[:remaining]
  end

  test "days remaining for cycle" do
    data = report
    cycle = PayCycle.current(@user)
    assert_equal (cycle.ends - Date.new(2026, 10, 28)).to_i, data[:days_remaining]
  end

  test "user isolation" do
    template(name: "Mine", amount: 100_000, payment_day: 28)
    template(name: "Theirs", amount: 500_000, user: @other)
    data = report
    assert_equal 1, data[:pending_expenses].size
  end

  test "empty state" do
    data = report
    assert_empty data[:pending_expenses]
    assert_equal 0.to_d, data[:pending_total]
  end
end