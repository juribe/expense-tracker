# frozen_string_literal: true

module Mcp
  module Tools
    module Expenses
      # GetExpenseTool
      # One expense scoped to the authenticated user.
      class GetExpenseTool < Mcp::ApplicationTool
        tool_name "get_expense"
        description "Return one expense by id."
        requires_scope :read

        arguments do
          required(:expense_id).filled(:string).description "Expense UUID."
        end

        def call(expense_id:)
          expense = user.expenses.includes(:category, :money_source).find(UuidParams.normalize(expense_id))
          success(Mcp::Presenters::TransactionPresenter.new(expense).as_json)
        end
      end
    end
  end
end
