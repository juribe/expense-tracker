# frozen_string_literal: true

require "test_helper"

module MoneySources
  class StatementMoneyTrackingTest < ActiveSupport::TestCase
    setup do
      @category = Category.create!(name: "Statement tracking", is_default: true, category_type: "expense")
      @income_category = Category.create!(name: "Statement income", is_default: true, category_type: "income")
    end

    test "simple General uses income and expense labels and hides advanced movements" do
      user = simple_user
      general = user.general_money_source
      destination = user.money_sources.create!(name: "Histórica", kind: "account", starting_balance: 0)
      user.expenses.create!(amount: 20_000, date: Date.current, description: "Gasto simple",
                            category: @category, source: "manual")
      user.incomes.create!(amount: 50_000, date: Date.current, description: "Ingreso simple",
                           category: @income_category, source: "manual")
      user.transfers.create!(from_source: general, to_source: destination, amount: 10_000, date: Date.current)

      statement = Statement.new(user: user, source: general).call

      assert statement.simple_general?
      assert_equal "Ingresos", statement.entries_label
      assert_equal "Gastos", statement.exits_label
      assert_equal [ "Gasto simple", "Ingreso simple" ].sort, statement.movements.map(&:description).sort
      refute_includes statement.movements.map(&:movement_type), "Transferencia enviada"
    end

    test "advanced sources keep the existing statement labels and transfers" do
      user = detailed_user
      account = user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 100_000)
      destination = user.money_sources.create!(name: "Otra", kind: "account", starting_balance: 0)
      user.transfers.create!(from_source: account, to_source: destination, amount: 10_000, date: Date.current)

      statement = Statement.new(user: user, source: account).call

      refute statement.simple_general?
      assert_equal "Entradas", statement.entries_label
      assert_equal "Salidas", statement.exits_label
      assert_equal [ "Transferencia enviada" ], statement.movements.map(&:movement_type)
    end

    private

    def simple_user
      User.create!(name: "Statement Simple", email: "statement_simple_#{SecureRandom.hex(4)}@example.com",
                   password: "password123").tap do |user|
        user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
      end
    end

    def detailed_user
      User.create!(name: "Statement Advanced", email: "statement_advanced_#{SecureRandom.hex(4)}@example.com",
                   password: "password123")
    end
  end
end
