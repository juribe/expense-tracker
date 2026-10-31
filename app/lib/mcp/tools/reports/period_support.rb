# frozen_string_literal: true

module Mcp
  module Tools
    module Reports
      # PeriodSupport
      # Builds the same reporting period the web reports use, including the
      # user's financial cycle when one is configured.
      module PeriodSupport
        private

        def reporting_period(month: nil, start_date: nil, end_date: nil)
          if start_date.present? || end_date.present?
            from = parse_date(start_date, field: "start_date") || Date.current.beginning_of_month
            to = parse_date(end_date, field: "end_date") || Date.current
            raise Mcp::Error.new("INVALID_DATE_RANGE", "start_date must be on or before end_date.") if to < from

            ::Reports::Period.new(preset: "custom", start_date: from, end_date: to, user: user)
          else
            anchor = month.present? ? parse_month(month) : Date.current
            ::Reports::Period.new(preset: "this_month", date: anchor, user: user)
          end
        end

        def report_filter(period)
          ::Reports::Filter.new(user: user, period: period)
        end

        def period_payload(period)
          {
            start_date: period.range.begin.iso8601,
            end_date: period.range.end.iso8601,
            label: period.label
          }
        end

        def money(value)
          Mcp::Presenters::Money.money(value)
        end
      end
    end
  end
end
