# frozen_string_literal: true

module Mcp
  module Tools
    module Expenses
      # CreateExpenseTool
      # Registers a structured expense through Expenses::Create, so every
      # existing validation, rule and balance update still applies.
      class CreateExpenseTool < Mcp::ApplicationTool
        tool_name "create_expense"
        description "Register an expense. Requires amount, date, category_id, money_source_id and description."
        requires_scope :write

        arguments do
          required(:amount).filled.description "Positive amount."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          required(:category_id).filled(:string).description "Expense category UUID."
          required(:money_source_id).filled(:string).description "Account, cash, wallet, debit or credit card UUID."
          optional(:description).filled(:string).description "Short description."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(amount:, date:, category_id:, money_source_id:, description: nil, idempotency_key: nil)
          category = find_category!(category_id, type: "expense")
          source = ensure_payment_source!(find_money_source!(money_source_id))
          occurred_on = required_date!(date)
          parsed_amount = positive_amount!(amount)
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { amount: parsed_amount.to_s("F"), date: occurred_on.iso8601,
                         category_id: category.id, money_source_id: source.id, description: description }
          ) do
            expense = ::Expenses::Create.call(
              user: user,
              amount: parsed_amount,
              description: description,
              category: category,
              occurred_at: occurred_on,
              source: "manual",
              money_source: source,
              idempotency_key: key
            )
            Mcp::Presenters::TransactionPresenter.new(expense).as_json
          end

          success(data)
        rescue ::Expenses::Create::Invalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.message)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new(record_error_code(e.record), e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
