# frozen_string_literal: true

# Reports::SpendingTrend
# Actual spending over time bucketed day/week/month (chosen by period span),
# zero-filled so charts render a continuous series; category filter applies.
#
# Methods: call
#
# Example: Reports::SpendingTrend.new(user: user, filter: filter).call[:series]
class Reports::SpendingTrend < Reports::Base
  BUCKET_LABELS = {
    day: "%d/%m/%Y", week: "%d/%m/%Y", month: "%b"
  }.freeze

  def call
    points = grouped_points
    filled = fill_missing(points)
    {
      period: period,
      bucket: period.bucket,
      total: filled.sum { |point| point[:total] },
      series: filled
    }
  end

  private

  def grouped_points
    base = filter.expense_scope(period.range).where.missing(:payments)
    base.group(bucket_sql)
        .pluck(Arel.sql(bucket_sql), Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
        .map do |bucket_date, total, count|
      { date: bucket_date.to_date, label: I18n.l(bucket_date.to_date, format: BUCKET_LABELS[period.bucket]),
        total: total.to_d, count: count.to_i }
    end.index_by { |point| point[:date] }
  end

  def bucket_sql
    case period.bucket
    when :day then "transactions.date"
    when :week then "date_trunc('week', transactions.date)"
    else "date_trunc('month', transactions.date)"
    end
  end

  def fill_missing(points)
    bucket_dates.map { |date| points[date] || empty_point(date) }
  end

  def bucket_dates
    case period.bucket
    when :day then period.range.to_a
    when :week then period_starts(7.days)
    else month_starts
    end
  end

  def period_starts(step)
    starts = [ period.range.first.beginning_of_week(:monday) ]
    last = period.range.last
    while (next_start = starts.last + step) <= last
      starts << next_start
    end
    starts
  end

  def month_starts
    starts = [ period.range.first.beginning_of_month ]
    last = period.range.last.beginning_of_month
    while (next_start = starts.last.next_month) <= last
      starts << next_start
    end
    starts
  end

  def empty_point(date)
    { date: date, label: I18n.l(date, format: BUCKET_LABELS[period.bucket]), total: 0.to_d, count: 0 }
  end
end
