# frozen_string_literal: true

# Reports::SpendingTrend
# Actual spending over time bucketed day/week/month (chosen by period span),
# zero-filled so charts render a continuous series; category filter applies.
#
# Methods: call
#
# Example: Reports::SpendingTrend.new(user: user, filter: filter).call[:series]
class Reports::SpendingTrend < Reports::Base
  include Reports::TimeBuckets

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

  def bucket
    period.bucket
  end

  def grouped_points
    base = filter.expense_scope(period.range).where.missing(:payments)
    base.group(bucket_sql)
        .pluck(Arel.sql(bucket_sql), Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
        .map do |bucket_date, total, count|
      { date: bucket_date.to_date, label: bucket_label(bucket_date.to_date),
        total: total.to_d, count: count.to_i }
    end.index_by { |point| point[:date] }
  end

  def fill_missing(points)
    bucket_dates.map { |date| points[date] || empty_point(date) }
  end

  def empty_point(date)
    { date: date, label: bucket_label(date), total: 0.to_d, count: 0 }
  end
end
