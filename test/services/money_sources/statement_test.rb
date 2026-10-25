# frozen_string_literal: true

require "test_helper"

class MoneySources::StatementTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Stmt User", email: "stmt_test@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1000)
  end

  test "opening balance uses starting balance" do
    result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    assert_equal BigDecimal("1000"), result.opening_balance
  end

  test "includes income and expense transactions" do
    @user.expenses.create!(money_source: @source, amount: 200, date: Date.current, description: "Gasto", source: "manual")
    @user.incomes.create!(money_source: @source, amount: 500, date: Date.current, description: "Ingreso", source: "manual")

    result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    assert_equal 2, result.total_count
    assert_equal BigDecimal("500"), result.entries_total
    assert_equal BigDecimal("200"), result.exits_total
  end

  test "transfer appears as out in origin and in in destination" do
    dest = @user.money_sources.create!(name: "Billetera", kind: "wallet", starting_balance: 0)
    transfer = Transfer.create!(user: @user, from_source: @source, to_source: dest, amount: 300, date: Date.current)

    origin_result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    dest_result = MoneySources::Statement.new(user: @user, source: dest, period: "current").call

    assert_equal 1, origin_result.total_count
    assert_equal "out", origin_result.movements.first.direction
    assert_equal 1, dest_result.total_count
    assert_equal "in", dest_result.movements.first.direction
  end

  test "search filters movements" do
    @user.expenses.create!(money_source: @source, amount: 100, date: Date.current, description: "Supermercado", source: "manual")
    @user.expenses.create!(money_source: @source, amount: 50, date: Date.current, description: "Transporte", source: "manual")

    result = MoneySources::Statement.new(user: @user, source: @source, period: "current", query: "super").call
    assert_equal 1, result.total_count
  end

  test "kind filter out" do
    @user.expenses.create!(money_source: @source, amount: 100, date: Date.current, description: "Gasto", source: "manual")
    @user.incomes.create!(money_source: @source, amount: 50, date: Date.current, description: "Ingreso", source: "manual")

    result = MoneySources::Statement.new(user: @user, source: @source, period: "current", kind: "out").call
    assert_equal 1, result.total_count
    assert_equal "out", result.movements.first.direction
  end

  test "pagination" do
    5.times do |i|
      @user.expenses.create!(money_source: @source, amount: 10, date: Date.current, description: "Gasto #{i}", source: "manual")
    end
    result = MoneySources::Statement.new(user: @user, source: @source, period: "current", per_page: 2, page: 2).call
    assert_equal 2, result.movements.size
    assert_equal 5, result.total_count
  end

  test "manual adjustment appears as movement" do
    BalanceAdjustment.create!(user: @user, money_source: @source, effective_date: Date.current, delta: 300, note: "Ajuste manual")
    result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    assert_equal 1, result.total_count
    assert_equal "Ajuste de saldo", result.movements.first.movement_type
    assert_equal "in", result.movements.first.direction
  end

  test "adjustment before period affects opening balance" do
    BalanceAdjustment.create!(user: @user, money_source: @source, effective_date: Date.current - 1.year, delta: 300, note: "Ajuste")
    result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    assert_equal BigDecimal("1300"), result.opening_balance
  end

  test "isolates users" do
    other = User.create!(name: "Other", email: "other_stmt@example.com", password: "password123")
    other_source = other.money_sources.create!(name: "Otra", kind: "account", starting_balance: 0)
    @user.expenses.create!(money_source: @source, amount: 100, date: Date.current, description: "Gasto", source: "manual")

    result = MoneySources::Statement.new(user: other, source: other_source, period: "current").call
    assert_equal 0, result.total_count
  end
end