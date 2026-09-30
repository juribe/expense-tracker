# frozen_string_literal: true

require "csv"
require "test_helper"

module Expenses
  class CsvExporterTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "CSV User", email: "csv_exporter@example.com", password: "password123")
      @category = Category.create!(name: "Comida", user: @user, is_default: false, category_type: "expense")
      @account = MoneySource.create!(user: @user, name: "Cuenta", kind: "account")
      Expense.create!(
        user: @user, category: @category, amount: 10_000, description: "Almuerzo",
        date: Date.new(2026, 1, 15), source: "manual", money_source: @account
      )
    end

    test "generates a header row and one row per expense" do
      rows = parsed_csv

      assert_equal %w[date description category amount source], rows.first
      assert_equal 2, rows.size
      row = rows.second
      assert_equal Date.new(2026, 1, 15), Date.parse(row[0])
      assert_equal "Almuerzo", row[1]
      assert_equal "Comida", row[2]
      assert_equal @account.name, row[4]
    end

    test "exports every expense of the scope, not only the current page" do
      30.times { |i| Expense.create!(user: @user, category: @category, amount: 1_000,
                                     description: "Relleno #{i}", date: Date.current, source: "manual") }

      # The controller always passes Expenses::Search#csv_scope, which is the
      # fully filtered relation before limit/offset were applied.
      result = Expenses::Search.call(user: @user, params: {})
      rows = CSV.parse(CsvExporter.call(result.csv_scope))

      # 30 fillers + the setup "Almuerzo" + the header row.
      assert_equal 32, rows.size
    end

    test "handles nil description, category, and money source" do
      Expense.create!(user: @user, category: nil, amount: 5_000, description: nil,
                      date: Date.new(2026, 1, 20), source: "ai")

      rows = parsed_csv
      last = rows.last
      assert_equal "", last[1]
      assert_equal "", last[2]
      assert_equal "", last[4]
    end

    test "provides the suggested download filename" do
      assert_equal "expenses-#{Date.today}.csv", CsvExporter.filename
    end

    private

    def parsed_csv
      scope = @user.expenses.order(date: :asc)
      CSV.parse(CsvExporter.call(scope))
    end
  end
end
