# frozen_string_literal: true

# Reports::SpendingTrend
# Actual spending over time bucketed by day, week or month. Daily totals are
# the single source of truth, so the indicators and every grouping stay
# consistent and no transaction is counted twice.
#
# Methods: call
#
# Example: Reports::SpendingTrend.new(user: user, filter: filter, granularity: "week").call[:series]
class Reports::SpendingTrend < Reports::Base
  GRANULARITIES = %w[day week month].freeze

  attr_reader :granularity

  def initialize(user:, filter:, granularity: nil)
    super(user: user, filter: filter)
    @granularity = resolve_granularity(granularity)
  end

  def call
    daily = daily_points
    total = daily.sum { |point| point[:total] }

    {
      period: period,
      bucket: bucket,
      granularity: granularity,
      total: total,
      transaction_count: daily.sum { |point| point[:count] },
      elapsed_days: elapsed_days,
      average_daily: average_daily(total),
      days_with_expenses: daily.count { |point| point[:total].positive? },
      peak: peak(daily),
      series: grouped_series(daily),
      daily_series: daily
    }
  end

  private

  def bucket
    granularity.to_sym
  end

  def resolve_granularity(value)
    candidate = value.to_s
    return candidate if GRANULARITIES.include?(candidate)

    period.bucket.to_s
  end

  def daily_points
    totals = daily_totals
    period.range.map do |date|
      total, count = totals.fetch(date, [ 0.to_d, 0 ])
      point(date, date, date, total, count)
    end
  end

  def daily_totals
    filter.actual_expense_scope(period.range)
          .group("transactions.date")
          .pluck(
            Arel.sql("transactions.date"),
            Arel.sql("ABS(SUM(transactions.amount))"),
            Arel.sql("COUNT(*)")
          )
          .to_h { |date, total, count| [ date.to_date, [ total.to_d, count.to_i ] ] }
  end

  def grouped_series(daily)
    return daily if bucket == :day

    daily.group_by { |point| bucket_date(point[:date]) }
         .map { |date, points| aggregate_point(date, points) }
         .sort_by { |point| point[:date] }
  end

  def bucket_date(date)
    bucket == :week ? date.beginning_of_week(:monday) : date.beginning_of_month
  end

  def aggregate_point(date, points)
    point(
      date,
      [ date, period.range.begin ].max,
      [ bucket_end(date), period.range.end ].min,
      points.sum { |entry| entry[:total] },
      points.sum { |entry| entry[:count] }
    )
  end

  def bucket_end(date)
    bucket == :week ? date + 6.days : date.end_of_month
  end

  def point(date, range_start, range_end, total, count)
    {
      date: date,
      label: label_for(date, range_start, range_end),
      total: total,
      count: count,
      range_start: range_start,
      range_end: range_end
    }
  end

  def label_for(date, range_start, range_end)
    case bucket
    when :week then week_label(range_start, range_end)
    when :month then I18n.l(date, format: "%B %Y")
    else I18n.l(date, format: "%d/%m/%Y")
    end
  end

  def week_label(range_start, range_end)
    if range_start.year == range_end.year
      "#{I18n.l(range_start, format: '%d %b')} – #{I18n.l(range_end, format: '%d %b')}"
    else
      "#{I18n.l(range_start, format: '%d %b %Y')} – #{I18n.l(range_end, format: '%d %b %Y')}"
    end
  end

  def elapsed_days
    return 0 if period.range.begin > Date.current

    ([ period.range.end, Date.current ].min - period.range.begin + 1).to_i
  end

  def average_daily(total)
    return 0.to_d if elapsed_days.zero?

    total / elapsed_days
  end

  def peak(daily)
    point = daily.select { |entry| entry[:total].positive? }.max_by { |entry| entry[:total] }
    return nil unless point

    point.slice(:date, :total, :count, :range_start, :range_end)
  end
end
