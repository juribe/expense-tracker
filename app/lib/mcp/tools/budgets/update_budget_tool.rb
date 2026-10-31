# frozen_string_literal: true

module Mcp
  module Tools
    module Budgets
      # UpdateBudgetTool
      # Changes a budget's limit, period or active state.
      class UpdateBudgetTool < Mcp::ApplicationTool
        tool_name "update_budget"
        description "Update a budget's amount, period or active state."
        requires_scope :write

        arguments do
          required(:budget_id).filled(:string).description "Budget UUID."
          optional(:amount).filled.description "New monthly limit."
          optional(:period).filled(:string, included_in?: Budget::PERIODS).description "Only monthly is supported."
          optional(:active).filled(:bool).description "Whether the budget is active."
        end

        def call(budget_id:, amount: nil, period: nil, active: nil)
          budget = user.budgets.includes(:category).find(UuidParams.normalize(budget_id))
          attributes = {}
          attributes[:monthly_amount] = positive_amount!(amount) if amount.present?
          attributes[:period] = period if period.present?
          attributes[:active] = active unless active.nil?

          budget.update!(attributes) if attributes.any?
          success(Mcp::Presenters::BudgetPresenter.new(budget.reload, date_range).as_json)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
