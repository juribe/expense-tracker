# frozen_string_literal: true

require "test_helper"

module Reconciliation
  class ExpenseSearchTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(
        name: "Reconciliation Search User",
        email: "reconciliation_expense_search_test@example.com",
        password: "password123"
      )
      @category = Category.create!(user: @user, name: "Servicios")
      @other_category = Category.create!(user: @user, name: "Transporte")
      @source = MoneySource.create!(user: @user, name: "Cuenta", kind: "account", starting_balance: 10_000_000)
      @template = RecurringTemplate.create!(
        user: @user, category: @category, kind: "expense", description: "Internet",
        amount: 180_000, frequency: "monthly", source: "manual", payment_day: 7
      )
    end

    def build_expense(attributes = {})
      Expense.create!(
        {
          user: @user,
          category: @category,
          description: "Pago Internet",
          amount: 180_000,
          kind: "expense",
          source: "manual",
          date: Date.current,
          money_source: @source
        }.merge(attributes)
      )
    end

    test "filters candidates by the recurring template category" do
      matching = build_expense
      build_expense(category: @other_category, description: "Pago Internet transporte")

      results = ExpenseSearch.call(
        user: @user, query: "Pago Internet", template_id: @template.id, period: Date.current.strftime("%Y-%m")
      )

      assert_equal [ matching.id ], results.map(&:id)
    end

    test "matches a numeric query against the amount" do
      matching = build_expense(amount: 180_000)
      build_expense(description: "Otro pago", amount: 500_000)

      results = ExpenseSearch.call(
        user: @user, query: "180000", template_id: @template.id, period: Date.current.strftime("%Y-%m")
      )

      assert_equal [ matching.id ], results.map(&:id)
    end

    test "excludes expenses already linked to a recurring template" do
      linked = build_expense
      linked.update!(recurring_template_id: @template.id)

      results = ExpenseSearch.call(
        user: @user, query: "Pago Internet", template_id: @template.id, period: Date.current.strftime("%Y-%m")
      )

      assert_empty results
    end

    test "returns no candidates when the template does not belong to the user" do
      other_user = User.create!(
        name: "Other User", email: "other_expense_search@example.com", password: "password123"
      )
      other_template = RecurringTemplate.create!(
        user: other_user, category: Category.create!(user: other_user, name: "Otros"),
        kind: "expense", description: "Otro", amount: 100_000, frequency: "monthly",
        source: "manual", payment_day: 1
      )
      build_expense

      results = ExpenseSearch.call(
        user: @user, query: "", template_id: other_template.id, period: Date.current.strftime("%Y-%m")
      )

      assert_empty results
    end
  end
end
