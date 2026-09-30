# frozen_string_literal: true

require "test_helper"

module Expenses
  class SearchTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Search User", email: "search@example.com", password: "password123")
      @category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
      @other_category = Category.create!(name: "Otra", user: @user, is_default: false, category_type: "expense")
      @account = MoneySource.create!(user: @user, name: "Cuenta", kind: "account")

      create_expense(date: Date.new(2026, 1, 15), amount: 50_000, description: "Almuerzo")
      create_expense(date: Date.new(2026, 2, 10), amount: 80_000, description: "Cena", category: @category)
      create_expense(date: Date.new(2026, 3, 5), amount: 20_000, description: "Transporte", money_source: @account)
    end

    def create_expense(**overrides)
      category = overrides.delete(:category) || @other_category
      money_source = overrides.delete(:money_source)
      user = overrides.delete(:user)
      Expense.create!(
        {
          user: user || @user,
          category: category || @category,
          amount: 10_000,
          description: "Gasto",
          date: Date.current,
          source: "manual",
          money_source: money_source
        }.merge(overrides)
      )
    end

    def search(params = {})
      Expenses::Search.call(user: @user, params: params)
    end

    test "returns all user expenses sorted by date desc by default" do
      result = search

      assert result.success?
      assert_equal [ "Transporte", "Cena", "Almuerzo" ], descriptions_of(result)
      assert_equal 3, result.total_count
      assert_equal BigDecimal("-150000"), result.filtered_total
    end

    test "rejects invalid filter ranges and does not query" do
      result = search(start_date: "2026-13-01", end_date: "2026-02-01")
      assert result.failure?
      assert result.filter_errors.key?(:start_date)
    end

    test "rejects from date after to date" do
      result = search(start_date: "2026-03-01", end_date: "2026-01-01")
      assert result.failure?
      assert_equal "From cannot be after To.", result.filter_errors[:start_date]
    end

    test "rejects min amount greater than max amount" do
      result = search(min_amount: "100", max_amount: "50")
      assert result.failure?
      assert result.filter_errors.key?(:min_amount)
    end

    test "filters by category" do
      result = search(category_id: @category.id)
      assert_equal [ "Cena" ], descriptions_of(result)
    end

    test "filters by date range" do
      result = search(start_date: "2026-01-01", end_date: "2026-02-28")
      assert_equal [ "Cena", "Almuerzo" ], descriptions_of(result)
    end

    test "filters by amount range using absolute value" do
      create_expense(amount: -60_000, description: "Pago con signo")

      result = search(min_amount: "55_000", max_amount: "70_000")
      assert_equal [ "Pago con signo" ], descriptions_of(result)
    end

    test "filters by money source" do
      result = search(money_source_id: @account.id)
      assert_equal [ "Transporte" ], descriptions_of(result)
    end

    test "applies amount filters with comma thousand separators" do
      result = search(min_amount: "70,000")
      assert_equal [ "Cena" ], descriptions_of(result)
    end

    test "sorts by amount asc with stable id tiebreaker" do
      @user.expenses.delete_all
      a = create_expense(description: "A", amount: 10_000)
      b = create_expense(description: "B", amount: 10_000)
      c = create_expense(description: "C", amount: 5_000)

      result = search(sort: "amount", dir: "asc")
      assert_equal [ c.id, a.id, b.id ], ids_of_sorted(result)
    end

    test "rejects an unknown sort column" do
      result = search(sort: "hacked; drop table", dir: "asc")
      assert result.success?
      assert_equal "date", result.sort
    end

    test "rejects an unknown sort direction" do
      result = search(sort: "amount", dir: "sideways")
      assert result.success?
      assert_equal "desc", result.dir
    end

    test "paginates the relation with will_paginate at the shared page size" do
      27.times { create_expense(description: "Relleno") }

      result = search(page: "2")
      assert_equal 25, result.relation.per_page
      assert_equal 2, result.relation.current_page
      assert_equal 30, result.total_count
    end

    test "exposes per-page subtotal of the current page" do
      27.times { create_expense(description: "Relleno", amount: 1_000) }

      result = search(page: "1")
      assert_equal BigDecimal("-25000"), result.page_subtotal
    end

    test "isolates expenses per user" do
      other = User.create!(name: "Otro", email: "other-search@example.com", password: "password123")
      create_expense(user: other, description: "Ajeno")

      result = search
      assert_equal 3, result.total_count
    end

    test "provides csv scope without limit/offset for exports" do
      27.times { create_expense(description: "Relleno") }

      result = search(page: "2")
      csv_scope = result.csv_scope
      assert_equal 30, csv_scope.count
    end

    private

    # descriptions ordered as the relation returns them (date desc)
    def descriptions_of(result)
      result.relation.map(&:description)
    end

    def ids_of_sorted(result)
      result.relation.map(&:id)
    end
  end
end
