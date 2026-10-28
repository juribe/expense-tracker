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

  test "current money includes accounts cash and wallets but excludes pockets cards loans" do
    @user.money_sources.create!(name: "Monedero", kind: "wallet", active: true, starting_balance: 250_000)

    data = report
    assert_equal 8_250_000.to_d, data[:current_money]
  end

  test "pending expenses are sorted by due date with no-date rows last" do
    @user.update!(financial_cycle_start_day: 20)
    template(name: "Later", amount: 100_000, payment_day: 10)
    template(name: "Sooner", amount: 100_000, payment_day: 28)
    template(name: "No date", amount: 100_000, payment_day: nil)

    names = report[:pending_expenses].map { |expense| expense[:name] }

    assert_equal [ "Sooner", "Later", "No date" ], names
  end

  test "due date metadata marks overdue today soon and no date rows" do
    @user.update!(financial_cycle_start_day: 20)
    template(name: "Overdue", amount: 100_000, payment_day: 20)
    template(name: "Today", amount: 100_000, payment_day: 28)
    template(name: "Soon", amount: 100_000, payment_day: 30)
    template(name: "No date", amount: 100_000, payment_day: nil)

    rows = report[:pending_expenses].index_by { |expense| expense[:name] }

    assert rows["Overdue"][:overdue]
    assert rows["Today"][:due_today]
    assert rows["Soon"][:due_soon]
    assert_nil rows["No date"][:due_date]
  end

  test "days remaining uses a configured cycle crossing into the next month" do
    @user.update!(financial_cycle_start_day: 20)

    data = report

    assert_equal Date.new(2026, 10, 20), data[:cycle].starts
    assert_equal Date.new(2026, 11, 19), data[:cycle].ends
    assert_equal 22, data[:days_remaining]
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
