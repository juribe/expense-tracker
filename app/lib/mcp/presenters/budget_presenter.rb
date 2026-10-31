# frozen_string_literal: true

module Mcp
  module Presenters
    # BudgetPresenter
    # Monthly target, actual spending and status for one category and period.
    # Accepts a precomputed spent amount so list tools can avoid one query per
    # budget.
    class BudgetPresenter
      include Mcp::Presenters::Money

      def initialize(budget, range, spent: nil)
        @budget = budget
        @range = range
        @spent = spent
      end

      def as_json
        amount = budget.amount_for(range)
        spent_value = @spent.nil? ? budget.spent_for(range) : @spent.to_d
        percentage = percentage_for(amount, spent_value)

        {
          id: budget.id,
          category: { id: budget.category.id, name: budget.category.name },
          period: budget.period,
          amount: money(amount),
          spent: money(spent_value),
          remaining: money(amount - spent_value),
          percentage: percentage,
          status: status_for(percentage).to_s
        }
      end

      private

      attr_reader :budget, :range

      def percentage_for(amount, spent)
        return 0.0 unless amount.to_f.positive?

        (spent / amount * 100).round(1).to_f
      end

      def status_for(percentage)
        return :over_budget if percentage > 100.0
        return :near_limit if percentage >= Budget::NEAR_LIMIT_PERCENT

        :on_track
      end
    end
  end
end
