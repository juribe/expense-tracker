# frozen_string_literal: true

module Mcp
  module Tools
    module Budgets
      # CreateBudgetTool
      # Creates a monthly spending target for an expense category.
      class CreateBudgetTool < Mcp::ApplicationTool
        tool_name "create_budget"
        description "Create a monthly budget for an expense category."
        requires_scope :write

        arguments do
          required(:category_id).filled(:string).description "Expense category UUID."
          required(:amount).filled.description "Monthly limit."
          optional(:period).filled(:string, included_in?: Budget::PERIODS).description "Only monthly is supported."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(category_id:, amount:, period: "monthly", idempotency_key: nil)
          category = find_category!(category_id, type: "expense")
          monthly_amount = positive_amount!(amount)
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { category_id: category.id, amount: monthly_amount.to_s("F"), period: period }
          ) do
            budget = user.budgets.create!(category: category, monthly_amount: monthly_amount, period: period)
            Mcp::Presenters::BudgetPresenter.new(budget, date_range).as_json
          end

          success(data)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
