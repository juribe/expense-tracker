# frozen_string_literal: true

module Mcp
  module Presenters
    # BudgetPresenter
    # Monthly target, actual spending and status for one category and period.
    class BudgetPresenter
      include Mcp::Presenters::Money

      def initialize(budget, range)
        @budget = budget
        @range = range
      end

      def as_json
        {
          id: budget.id,
          category: { id: budget.category.id, name: budget.category.name },
          period: budget.period,
          amount: money(budget.amount_for(range)),
          spent: money(budget.spent_for(range)),
          remaining: money(budget.remaining_for(range)),
          percentage: budget.percentage_for(range).to_f.round(1),
          status: budget.status_for(range).to_s
        }
      end

      private

      attr_reader :budget, :range
    end
  end
end
