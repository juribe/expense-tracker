# frozen_string_literal: true

# Reports::Perspectives::Evolution
# Compact historical view for the perspectives page: the last cycles or
# calendar months ending with the selected period, using the same user,
# category and money-source filters as every other block. Totals are read in
# one grouped daily query and folded into the requested periods in memory.
#
# Methods: call
#
# Example: Reports::Perspectives::Evolution.new(user: user, filter: filter).call[:series]
class Reports::Perspectives::Evolution
  PERIODS = Reports::Perspectives::Thresholds::EVOLUTION_PERIODS

  def initialize(user:, filter:)
    @user = user
    @filter = filter
    @period = filter.period
  end

  attr_reader :user, :filter, :period

  def call
    series = ranges.map { |range| point(range) }
    current = series.last
    previous = series[-2]

    {
      series: series,
      total: current ? current[:total] : 0.to_d,
      previous_total: previous ? previous[:total] : nil,
      delta_pct: delta_pct(current, previous)
    }
  end

  private

  def ranges
    return calendar_ranges unless Reports::Period.cycles_enabled?(user)

    PayCycle.back(user, PERIODS, anchor: period.range.end).map(&:to_range)
  end

  def calendar_ranges
    end_month = period.range.end.beginning_of_month
    (PERIODS - 1).downto(0).map do |months_back|
      start = end_month - months_back.months
      start..start.end_of_month
    end
  end

  def point(range)
    {
      label: I18n.l(range.begin, format: "%b %Y"),
      short_label: I18n.l(range.begin, format: "%b"),
      total: totals_for(range),
      range: range,
      current: range == period.range
    }
  end

  def totals_for(range)
    daily_totals.select { |date, _total| range.cover?(date) }.sum(0.to_d) { |_date, total| total }
  end

  def daily_totals
    @daily_totals ||= filter.actual_expense_scope(overall_range)
                            .group("transactions.date")
                            .pluck(Arel.sql("transactions.date"), Arel.sql("ABS(SUM(transactions.amount))"))
                            .map { |date, total| [ date.to_date, total.to_d ] }
  end

  def overall_range
    @overall_range ||= ranges.first.begin..ranges.last.end
  end

  def delta_pct(current, previous)
    return nil unless current && previous

    previous_total = previous[:total].to_d
    return nil if previous_total.zero?

    ((current[:total].to_d - previous_total) / previous_total * 100).round(1)
  end
end
