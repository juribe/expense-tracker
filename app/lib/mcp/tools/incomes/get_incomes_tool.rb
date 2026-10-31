# frozen_string_literal: true

module Mcp
  module Tools
    module Incomes
      # GetIncomesTool
      # Recent incomes with date, category and source filters plus pagination.
      class GetIncomesTool < Mcp::ApplicationTool
        tool_name "get_incomes"
        description "List incomes for a period. Defaults to the current month or financial cycle."
        requires_scope :read

        arguments do
          optional(:start_date).filled(:string).description "ISO date (YYYY-MM-DD)."
          optional(:end_date).filled(:string).description "ISO date (YYYY-MM-DD)."
          optional(:category_id).filled(:string).description "Income category UUID."
          optional(:money_source_id).filled(:string).description "Money source UUID."
          optional(:limit).filled(:integer, gt?: 0, lteq?: 100).description "Page size (max 100)."
          optional(:offset).filled(:integer, gteq?: 0).description "Rows to skip."
        end

        def call(start_date: nil, end_date: nil, category_id: nil, money_source_id: nil, limit: 25, offset: 0)
          range = date_range(start_date: start_date, end_date: end_date)
          scope = Income.for_user(user).where(date: range)
          scope = scope.where(category_id: find_category!(category_id, type: "income").id) if category_id.present?
          scope = scope.where(money_source_id: find_money_source!(money_source_id).id) if money_source_id.present?

          incomes, pagination = paginated(
            scope.includes(:category, :money_source).order(date: :desc, created_at: :desc),
            limit: limit, offset: offset
          )

          success(
            incomes: incomes.map { |income| Mcp::Presenters::TransactionPresenter.new(income).as_json },
            pagination: pagination
          )
        end
      end
    end
  end
end
