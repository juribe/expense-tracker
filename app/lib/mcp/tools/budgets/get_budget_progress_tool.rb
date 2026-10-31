# frozen_string_literal: true

module Mcp
  module Tools
    module Budgets
      # GetBudgetProgressTool
      # Progress for every active budget, or for one budget when asked.
      class GetBudgetProgressTool < Mcp::ApplicationTool
        tool_name "get_budget_progress"
        description "Return budget execution for the period. Optionally limit it to one budget."
        requires_scope :read

        arguments do
          optional(:budget_id).filled(:string).description "Budget UUID."
          optional(:month).filled(:string).description "Month in YYYY-MM format."
          optional(:start_date).filled(:string).description "ISO start date."
          optional(:end_date).filled(:string).description "ISO end date."
        end

        def call(budget_id: nil, month: nil, start_date: nil, end_date: nil)
          range = date_range(start_date: start_date, end_date: end_date, month: month)
          budgets =
            if budget_id.present?
              [ user.budgets.includes(:category).find(UuidParams.normalize(budget_id)) ]
            else
              user.budgets.active.includes(:category).order(:created_at).to_a
            end

          success(
            budgets: budgets.map { |budget| Mcp::Presenters::BudgetPresenter.new(budget, range).as_json },
            period: { start_date: range.begin.iso8601, end_date: range.end.iso8601 }
          )
        end
      end
    end
  end
end
