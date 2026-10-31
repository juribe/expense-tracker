# frozen_string_literal: true

module Mcp
  module Tools
    module Expenses
      # DeleteExpenseTool
      # Destructive and therefore explicit: requires confirm and refuses
      # expenses already applied to a debt, whose deletion would reverse a
      # payment.
      class DeleteExpenseTool < Mcp::ApplicationTool
        tool_name "delete_expense"
        description "Delete an expense. Requires confirm=true."
        requires_scope :write

        arguments do
          required(:expense_id).filled(:string).description "Expense UUID."
          optional(:confirm).filled(:bool).description "Must be true to delete."
        end

        def call(expense_id:, confirm: false)
          expense = user.expenses.find(UuidParams.normalize(expense_id))

          unless confirm
            raise Mcp::Error.new("OPERATION_NOT_ALLOWED", "Set confirm=true to delete the expense.")
          end
          if expense.payments.exists?
            raise Mcp::Error.new("OPERATION_NOT_ALLOWED",
                                 "An expense applied to a debt cannot be deleted. Remove the payment first.")
          end

          expense.destroy!
          success(id: expense.id, deleted: true)
        end
      end
    end
  end
end
