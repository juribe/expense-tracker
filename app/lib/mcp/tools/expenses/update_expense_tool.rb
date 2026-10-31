# frozen_string_literal: true

module Mcp
  module Tools
    module Expenses
      # UpdateExpenseTool
      # Changes an existing expense. Applied debt payments protect the fields
      # that define their accounting (amount, date and money source).
      class UpdateExpenseTool < Mcp::ApplicationTool
        tool_name "update_expense"
        description "Update an expense's amount, date, category, money source or description."
        requires_scope :write

        arguments do
          required(:expense_id).filled(:string).description "Expense UUID."
          optional(:amount).filled.description "New positive amount."
          optional(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          optional(:category_id).filled(:string).description "Expense category UUID."
          optional(:money_source_id).filled(:string).description "Money source UUID."
          optional(:description).filled(:string).description "Short description."
        end

        def call(expense_id:, amount: nil, date: nil, category_id: nil, money_source_id: nil, description: nil)
          expense = user.expenses.includes(:category, :money_source).find(UuidParams.normalize(expense_id))
          changes = { amount: amount, date: date, money_source_id: money_source_id }

          if expense.payments.exists? && changes.values.any?(&:present?)
            raise Mcp::Error.new("OPERATION_NOT_ALLOWED",
                                 "An expense applied to a debt cannot change its amount, date or source.")
          end

          attributes = {}
          attributes[:amount] = positive_amount!(amount) if amount.present?
          attributes[:date] = required_date!(date) if date.present?
          attributes[:category] = find_category!(category_id, type: "expense") if category_id.present?
          if money_source_id.present?
            attributes[:money_source] = ensure_payment_source!(find_money_source!(money_source_id))
          end
          attributes[:description] = description if description.present?

          expense.update!(attributes) if attributes.any?
          success(Mcp::Presenters::TransactionPresenter.new(expense.reload).as_json)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
