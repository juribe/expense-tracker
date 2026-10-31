# frozen_string_literal: true

module Mcp
  module Tools
    module Budgets
      # GetBudgetDetailsTool
      # One budget for the requested period.
      class GetBudgetDetailsTool < Mcp::ApplicationTool
        tool_name "get_budget_details"
        description "Return one budget with limit, spent, remaining and execution percentage."
        requires_scope :read

        arguments do
          required(:budget_id).filled(:string).description "Budget UUID."
          optional(:month).filled(:string).description "Month in YYYY-MM format."
          optional(:start_date).filled(:string).description "ISO start date."
          optional(:end_date).filled(:string).description "ISO end date."
        end

        def call(budget_id:, month: nil, start_date: nil, end_date: nil)
          budget = user.budgets.includes(:category).find(UuidParams.normalize(budget_id))
          range = date_range(start_date: start_date, end_date: end_date, month: month)

          success(Mcp::Presenters::BudgetPresenter.new(budget, range).as_json)
        end
      end
    end
  end
end
