# frozen_string_literal: true

# Reports::CashFlowTrend
# Income versus actual consumption spending over the selected period, grouped
# into day/week/month buckets. Debt payments are excluded from expenses, the
# same accounting split every report uses, so the chart never counts a debt
# payment as consumption. Buckets are zero-filled for a continuous series.
#
# Methods: call
#
# Example: Reports::CashFlowTrend.new(user: user, filter: filter).call[:series]
class Reports::CashFlowTrend < Reports::Base
  include Reports::TimeBuckets

  DAILY_BUCKET_LIMIT = 14

  def call
    series = bucket_dates.map { |date| point_for(date) }
    {
      period: period,
      bucket: bucket,
      total_income: series.sum { |point| point[:income] },
      total_expense: series.sum { |point| point[:expense] },
      series: series
    }
  end

  private

  # Short custom ranges read better day by day; cycles and multi-month spans
  # are compared week by week, and long horizons month by month.
  def bucket
    @bucket ||= if span_days <= DAILY_BUCKET_LIMIT
      :day
    elsif span_days <= Reports::Period::WEEK_BUCKET_LIMIT
      :week
    else
      :month
    end
  end

  def span_days
    (period.range.end - period.range.begin + 1).to_i
  end

  # Weeks in this chart start on the first day of the selected period, so
  # every cycle week groups its own movements together.
  def week_origin
    period.range.begin
  end

  def point_for(date)
    {
      date: date,
      label: bucket_label(label_date(date)),
      income: income_by_bucket.fetch(date, 0.to_d),
      expense: expense_by_bucket.fetch(date, 0.to_d)
    }
  end

  # Daily and weekly buckets use short labels so mobile axes stay readable.
  def bucket_label_format
    bucket == :month ? "%b" : "%d/%m"
  end

  # The first weekly bucket can start before the period (Monday); label it
  # with the actual first day of activity instead.
  def label_date(date)
    bucket == :week ? [ date, period.range.begin ].max : date
  end

  def income_by_bucket
    @income_by_bucket ||= grouped_totals(filter.income_scope(period.range))
  end

  def expense_by_bucket
    @expense_by_bucket ||= grouped_totals(actual_expenses)
  end
end
