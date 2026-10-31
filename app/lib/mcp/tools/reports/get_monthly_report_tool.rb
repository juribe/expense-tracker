# frozen_string_literal: true

module Mcp
  module Tools
    module Reports
      # GetMonthlyReportTool
      # Period overview: income, expenses, debt payments, transfers and net cash
      # flow, reusing Reports::Overview.
      class GetMonthlyReportTool < Mcp::ApplicationTool
        include Mcp::Tools::Reports::PeriodSupport

        tool_name "get_monthly_report"
        description "Summarize income, expenses, debt payments and net cash flow for a month or custom range."
        requires_scope :read

        arguments do
          optional(:month).filled(:string).description "Month in YYYY-MM format (default current month/cycle)."
          optional(:start_date).filled(:string).description "ISO start date."
          optional(:end_date).filled(:string).description "ISO end date."
        end

        def call(month: nil, start_date: nil, end_date: nil)
          period = reporting_period(month: month, start_date: start_date, end_date: end_date)
          report = ::Reports::Overview.new(user: user, filter: report_filter(period)).call

          success(
            period: period_payload(report[:period]),
            income: {
              total: money(report[:income][:total]),
              previous: money(report[:income][:previous]),
              delta_pct: report[:income][:delta_pct]&.to_f,
              count: report[:income][:count]
            },
            expenses: {
              total: money(report[:expenses][:total]),
              previous: money(report[:expenses][:previous]),
              delta_pct: report[:expenses][:delta_pct]&.to_f,
              count: report[:expenses][:count],
              average: money(report[:expenses][:average])
            },
            debt_payments: {
              total: money(report[:debt][:total]),
              principal: money(report[:debt][:principal]),
              interest: money(report[:debt][:interest])
            },
            transfers: {
              total: money(report[:transfers][:total]),
              count: report[:transfers][:count]
            },
            net_cash_flow: money(report[:net_cash_flow])
          )
        end
      end
    end
  end
end
