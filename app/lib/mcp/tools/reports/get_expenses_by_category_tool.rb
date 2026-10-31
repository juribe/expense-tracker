# frozen_string_literal: true

module Mcp
  module Tools
    module Reports
      # GetExpensesByCategoryTool
      # Actual spending per category, excluding debt payments (the same
      # accounting split every web report uses).
      class GetExpensesByCategoryTool < Mcp::ApplicationTool
        include Mcp::Tools::Reports::PeriodSupport

        tool_name "get_expenses_by_category"
        description "Group actual expenses by category for a period, with totals and share."
        requires_scope :read

        arguments do
          optional(:month).filled(:string).description "Month in YYYY-MM format."
          optional(:start_date).filled(:string).description "ISO start date."
          optional(:end_date).filled(:string).description "ISO end date."
        end

        def call(month: nil, start_date: nil, end_date: nil)
          period = reporting_period(month: month, start_date: start_date, end_date: end_date)
          report = ::Reports::CategorySpending.new(user: user, filter: report_filter(period)).call

          success(
            period: period_payload(report[:period]),
            total: money(report[:total]),
            categories: report[:categories].map do |row|
              {
                id: row[:id],
                name: row[:name],
                total: money(row[:total]),
                count: row[:count],
                share_pct: row[:share_pct]&.to_f,
                previous: money(row[:previous]),
                delta_pct: row[:delta_pct]&.to_f
              }
            end
          )
        end
      end
    end
  end
end
