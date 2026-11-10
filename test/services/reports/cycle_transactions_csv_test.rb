# frozen_string_literal: true

require "test_helper"
require "csv"

class ReportsCycleTransactionsCsvTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Cycle CSV", email: "cycle_csv_test@example.com", password: "password123")
    @income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @expense_category = Category.create!(name: "Mercado", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Banco", kind: "account", active: true, starting_balance: 10_000_000)
  end

  test "exports only the received transactions with their type and signed value" do
    income = Income.create!(user: @user, category: @income_category, money_source: @bank, amount: 2_000_000,
                            date: Date.new(2026, 10, 21), description: "Nómina", source: "manual")
    expense = Expense.create!(user: @user, category: @expense_category, money_source: @bank, amount: -100_000,
                              date: Date.new(2026, 10, 22), description: "Mercado", source: "manual")

    rows = CSV.parse(Reports::CycleTransactionsCsv.new(records: [ income, expense ]).call)

    assert_equal [ "Fecha", "Tipo", "Descripción", "Categoría", "Valor" ], rows.first
    assert_equal [ "2026-10-21", "Ingreso", "Nómina", "Salario", "2000000.0" ], rows[1]
    assert_equal [ "2026-10-22", "Gasto", "Mercado", "Mercado", "-100000.0" ], rows[2]
  end
end
