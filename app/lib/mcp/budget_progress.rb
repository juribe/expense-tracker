# frozen_string_literal: true

module Mcp
  # BudgetProgress
  # Builds budget progress with one grouped spending query instead of one
  # query per budget (Budget#spent_for runs a query per instance).
  #
  # Example: Mcp::BudgetProgress.new(user: user, range: range).call
  class BudgetProgress
    def initialize(user:, range:, budgets: nil)
      @user = user
      @range = range
      @budgets = budgets
    end

    def call
      budgets = @budgets || @user.budgets.active.includes(:category).order(:created_at).to_a
      spending = spending_by_category(budgets.map(&:category_id))

      budgets.map do |budget|
        Mcp::Presenters::BudgetPresenter.new(
          budget, @range, spent: spending.fetch(budget.category_id, 0)
        ).as_json
      end
    end

    private

    def spending_by_category(category_ids)
      ids = category_ids.compact.uniq
      return {} if ids.empty?

      Expense.for_user(@user)
             .where(date: @range, category_id: ids)
             .group(:category_id)
             .sum(Arel.sql("ABS(transactions.amount)"))
             .transform_values(&:to_d)
    end
  end
end
