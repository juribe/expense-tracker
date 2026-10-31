# frozen_string_literal: true

module Mcp
  module Tools
    module Budgets
      # GetBudgetsTool
      # Active budgets with the period's spending, remaining amount and status.
      class GetBudgetsTool < Mcp::ApplicationTool
        tool_name "get_budgets"
        description "List active budgets with limit, spent, remaining and execution percentage."
        requires_scope :read

        arguments do
          optional(:month).filled(:string).description "Month in YYYY-MM format (default current month/cycle)."
          optional(:start_date).filled(:string).description "ISO start date."
          optional(:end_date).filled(:string).description "ISO end date."
        end

        def call(month: nil, start_date: nil, end_date: nil)
          range = date_range(start_date: start_date, end_date: end_date, month: month)
          budgets = Mcp::BudgetProgress.new(user: user, range: range).call

          success(budgets: budgets, period: { start_date: range.begin.iso8601, end_date: range.end.iso8601 })
        end
      end
    end
  end
end
