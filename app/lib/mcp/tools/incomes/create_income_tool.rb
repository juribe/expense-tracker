# frozen_string_literal: true

module Mcp
  module Tools
    module Incomes
      # CreateIncomeTool
      # Registers a structured income through the existing Income model.
      class CreateIncomeTool < Mcp::ApplicationTool
        tool_name "create_income"
        description "Register an income. Requires amount, date, category_id, money_source_id and description."
        requires_scope :write

        arguments do
          required(:amount).filled.description "Positive amount."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          required(:category_id).filled(:string).description "Income category UUID."
          required(:money_source_id).filled(:string).description "Destination money source UUID."
          optional(:description).filled(:string).description "Short description."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(amount:, date:, category_id:, money_source_id:, description: nil, idempotency_key: nil)
          category = find_category!(category_id, type: "income")
          source = ensure_payment_source!(find_money_source!(money_source_id))
          occurred_on = required_date!(date)
          parsed_amount = positive_amount!(amount)
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { amount: parsed_amount.to_s("F"), date: occurred_on.iso8601,
                         category_id: category.id, money_source_id: source.id, description: description }
          ) do
            income = Income.create!(
              user: user,
              category: category,
              money_source: source,
              amount: parsed_amount,
              date: occurred_on,
              description: description,
              source: "manual",
              idempotency_key: key
            )
            Mcp::Presenters::TransactionPresenter.new(income).as_json
          end

          success(data)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
