# frozen_string_literal: true

module Mcp
  module Tools
    module Incomes
      # GetIncomeTool
      # One income scoped to the authenticated user.
      class GetIncomeTool < Mcp::ApplicationTool
        tool_name "get_income"
        description "Return one income by id."
        requires_scope :read

        arguments do
          required(:income_id).filled(:string).description "Income UUID."
        end

        def call(income_id:)
          income = user.incomes.includes(:category, :money_source).find(UuidParams.normalize(income_id))
          success(Mcp::Presenters::TransactionPresenter.new(income).as_json)
        end
      end
    end
  end
end
