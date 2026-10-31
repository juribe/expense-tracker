# frozen_string_literal: true

module Mcp
  module Tools
    module Incomes
      # UpdateIncomeTool
      # Changes an existing income. No debt protection applies here: incomes
      # never carry a Payment.
      class UpdateIncomeTool < Mcp::ApplicationTool
        tool_name "update_income"
        description "Update an income's amount, date, category, money source or description."
        requires_scope :write

        arguments do
          required(:income_id).filled(:string).description "Income UUID."
          optional(:amount).filled.description "New positive amount."
          optional(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          optional(:category_id).filled(:string).description "Income category UUID."
          optional(:money_source_id).filled(:string).description "Money source UUID."
          optional(:description).filled(:string).description "Short description."
        end

        def call(income_id:, amount: nil, date: nil, category_id: nil, money_source_id: nil, description: nil)
          income = user.incomes.includes(:category, :money_source).find(UuidParams.normalize(income_id))

          attributes = {}
          attributes[:amount] = positive_amount!(amount) if amount.present?
          attributes[:date] = required_date!(date) if date.present?
          attributes[:category] = find_category!(category_id, type: "income") if category_id.present?
          if money_source_id.present?
            attributes[:money_source] = ensure_payment_source!(find_money_source!(money_source_id))
          end
          attributes[:description] = description if description.present?

          income.update!(attributes) if attributes.any?
          success(Mcp::Presenters::TransactionPresenter.new(income.reload).as_json)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
