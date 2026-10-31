# frozen_string_literal: true

module Mcp
  module Tools
    module Reports
      # GetIncomeVsExpensesTool
      # Income and consumption spending side by side with their net result.
      class GetIncomeVsExpensesTool < Mcp::ApplicationTool
        include Mcp::Tools::Reports::PeriodSupport

        tool_name "get_income_vs_expenses"
        description "Compare income against expenses for a period, including the net cash flow."
        requires_scope :read

        arguments do
          optional(:month).filled(:string).description "Month in YYYY-MM format."
          optional(:start_date).filled(:string).description "ISO start date."
          optional(:end_date).filled(:string).description "ISO end date."
        end

        def call(month: nil, start_date: nil, end_date: nil)
          period = reporting_period(month: month, start_date: start_date, end_date: end_date)
          report = ::Reports::Overview.new(user: user, filter: report_filter(period)).call

          success(
            period: period_payload(report[:period]),
            income_total: money(report[:income][:total]),
            expenses_total: money(report[:expenses][:total]),
            net_cash_flow: money(report[:net_cash_flow]),
            income_delta_pct: report[:income][:delta_pct]&.to_f,
            expenses_delta_pct: report[:expenses][:delta_pct]&.to_f,
            previous: {
              income_total: money(report[:income][:previous]),
              expenses_total: money(report[:expenses][:previous])
            }
          )
        end
      end
    end
  end
end
