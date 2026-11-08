# frozen_string_literal: true

require "test_helper"

class MonthlyReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Monthly Reports User", email: "monthly_reports_test@example.com",
                         password: "password123")
    @account = MoneySource.create!(user: @user, name: "Davibank", kind: "account", starting_balance: 10_000_000)
    @category = Category.create!(user: @user, name: "Mercado")
  end

  test "show loads categories without an N+1 query" do
    categories = [ @category, Category.create!(user: @user, name: "Transporte"),
                   Category.create!(user: @user, name: "Ocio") ]
    categories.each_with_index do |category, index|
      @user.expenses.create!(
        category: category, description: "Compra #{index}", amount: 50_000,
        kind: "expense", source: "manual", date: Date.new(2026, 10, 10 + index),
        money_source: @account
      )
    end
    @user.incomes.create!(
      category: Category.create!(user: @user, name: "Salario"), description: "Salario",
      amount: 3_000_000, kind: "income", source: "manual", date: Date.new(2026, 10, 15),
      money_source: @account
    )
    sign_in @user

    category_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      category_queries << payload[:sql] if payload[:sql].match?(/FROM "categories"/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get monthly_report_path("2026-10")
    end

    assert_response :success
    # One preload per relation (incomes + expenses), regardless of how many
    # transactions the month has.
    assert_equal 2, category_queries.size
  end

  test "index uses the shared cycle filter and groups transactions by financial cycle" do
    @user.update!(financial_cycle_start_day: 20)
    @user.expenses.create!(
      category: @category, description: "Dentro del ciclo", amount: 100_000,
      kind: "expense", source: "manual", date: Date.new(2026, 10, 25), money_source: @account
    )
    @user.expenses.create!(
      category: @category, description: "Ciclo anterior", amount: 50_000,
      kind: "expense", source: "manual", date: Date.new(2026, 9, 15), money_source: @account
    )
    sign_in @user

    travel_to Date.new(2026, 11, 8) do
      get monthly_reports_path
    end

    assert_response :success
    assert_select "select#report-period-select option[value=this_cycle]"
    assert_select "[data-testid=monthly-balance-table] tbody tr", count: 1
    assert_select "[data-testid=monthly-balance-table]", text: /Octubre 2026/
    assert_select "[data-testid=monthly-balance-table]", text: /\$100\.000/
  end

  test "show renders only the cycle transactions in a sortable table" do
    @user.update!(financial_cycle_start_day: 20)
    @user.expenses.create!(
      category: @category, description: "Dentro del ciclo", amount: 100_000,
      kind: "expense", source: "manual", date: Date.new(2026, 10, 25), money_source: @account
    )
    @user.expenses.create!(
      category: @category, description: "Ciclo anterior", amount: 50_000,
      kind: "expense", source: "manual", date: Date.new(2026, 10, 19), money_source: @account
    )
    sign_in @user

    get monthly_report_path("2026-10-20")

    assert_response :success
    assert_select "[data-sortable-table] [data-sort-key]", count: 5
    assert_select "[data-testid=monthly-balance-transactions-table] tbody tr", count: 1
    assert_select "[data-testid=monthly-balance-transactions-table]", text: /Dentro del ciclo/
    assert_no_match(/Ciclo anterior/, response.body)
  end
end
