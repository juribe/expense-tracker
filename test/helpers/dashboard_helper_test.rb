# frozen_string_literal: true

require "test_helper"

class DashboardHelperTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    @user = User.create!(name: "Helper User", email: "dashboard_helper_test@example.com", password: "password123")
    @category = Category.create!(name: "Comida", is_default: true, category_type: "expense")
    @money_source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 10_000_000)
  end

  test "dashboard_signed_currency prefixes positive and negative amounts" do
    assert_equal "+$17.000.000", dashboard_signed_currency(17_000_000)
    assert_equal "-$500.000", dashboard_signed_currency(-500_000)
  end

  test "dashboard_period_filter uses the cycle selector with a configured schedule" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.new(2026, 10, 25))

    filter = dashboard_period_filter(user: @user, cycle: cycle, month: nil)

    assert_equal :cycle, filter[:param]
    assert_equal "2026-10-20", filter[:selected]
    assert_includes filter[:options].map(&:last), "2026-10-20"
  end

  test "dashboard_period_filter uses the month selector without a configured schedule" do
    filter = dashboard_period_filter(user: @user, cycle: nil, month: Date.new(2026, 11, 1))

    assert_equal :month, filter[:param]
    assert_equal "2026-11", filter[:selected]
    assert_includes filter[:options].map(&:last), "2026-11"
  end

  test "dashboard_budget_summary aggregates budget, spent, remaining and usage" do
    other = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    Budget.create!(user: @user, category: @category, monthly_amount: 100_000, period: "monthly", active: true)
    Budget.create!(user: @user, category: other, monthly_amount: 200_000, period: "monthly", active: true)
    @user.expenses.create!(amount: 80_000, date: Date.new(2026, 11, 3), category: @category,
                           description: "Comida", money_source: @money_source)
    @user.expenses.create!(amount: 50_000, date: Date.new(2026, 11, 4), category: other,
                           description: "Bus", money_source: @money_source)

    summary = dashboard_budget_summary(@user.budgets, Date.new(2026, 11, 1))

    assert_in_delta 300_000, summary[:total], 0.01
    assert_in_delta 130_000, summary[:spent], 0.01
    assert_in_delta 170_000, summary[:remaining], 0.01
    assert_in_delta 43.33, summary[:percentage], 0.01
    assert_equal :on_track, summary[:status]
  end

  test "dashboard_budget_summary flags budgets near the limit and over budget" do
    Budget.create!(user: @user, category: @category, monthly_amount: 100_000, period: "monthly", active: true)
    @user.expenses.create!(amount: 85_000, date: Date.new(2026, 11, 3), category: @category,
                           description: "Comida", money_source: @money_source)

    near_limit = dashboard_budget_summary(@user.budgets, Date.new(2026, 11, 1))
    assert_equal :near_limit, near_limit[:status]

    @user.expenses.create!(amount: 30_000, date: Date.new(2026, 11, 4), category: @category,
                           description: "Más comida", money_source: @money_source)

    over_budget = dashboard_budget_summary(@user.budgets.reload, Date.new(2026, 11, 1))
    assert_equal :over_budget, over_budget[:status]
    assert_in_delta 0, over_budget[:remaining], 0.01
  end

  test "dashboard_money_source_badge shows the source name or a dash" do
    source = @user.money_sources.create!(name: "Tarjeta débito", kind: "debit_card", starting_balance: 0)

    assert_match(/Tarjeta débito/, dashboard_money_source_badge(source))
    assert_match(/ti-credit-card/, dashboard_money_source_badge(source))
    assert_match(/—/, dashboard_money_source_badge(nil))
  end
end
