# frozen_string_literal: true

require "test_helper"

class ReportsSpendingTrendInsightsTest < ActiveSupport::TestCase
  def trend_for(range, totals, counts: {})
    days = range.to_a
    daily_series = days.map do |date|
      { date: date, total: totals.fetch(date, 0).to_d, count: counts.fetch(date, 0) }
    end
    total = daily_series.sum { |point| point[:total] }

    {
      total: total,
      daily_series: daily_series,
      elapsed_days: days.size,
      average_daily: days.size.positive? ? total / days.size : 0.to_d,
      days_with_expenses: daily_series.count { |point| point[:total].positive? }
    }
  end

  def insight(trend, key)
    Reports::SpendingTrendInsights.new(trend: trend).call[:items].find { |item| item[:key] == key }
  end

  test "concentration names the peak day only with enough spending days" do
    range = Date.new(2026, 9, 1)..Date.new(2026, 9, 10)
    trend = trend_for(range, {
      Date.new(2026, 9, 2) => 500_000,
      Date.new(2026, 9, 5) => 200_000,
      Date.new(2026, 9, 8) => 300_000
    })

    item = insight(trend, :concentration)

    assert item[:available]
    assert_includes item[:body], "2 de septiembre"
    assert_includes item[:body], "50"
  end

  test "concentration stays neutral with a small sample" do
    range = Date.new(2026, 9, 1)..Date.new(2026, 9, 2)
    trend = trend_for(range, { Date.new(2026, 9, 1) => 100_000 })

    item = insight(trend, :concentration)

    refute item[:available]
    assert_equal I18n.t("reports.trend.insights.insufficient"), item[:body]
  end

  test "exceptional spending compares the peak day against the daily average" do
    range = Date.new(2026, 9, 1)..Date.new(2026, 9, 10)
    trend = trend_for(range, {
      Date.new(2026, 9, 6) => 600_000,
      Date.new(2026, 9, 2) => 30_000,
      Date.new(2026, 9, 4) => 30_000,
      Date.new(2026, 9, 9) => 30_000
    })

    item = insight(trend, :exceptional)

    assert item[:available]
    assert_includes item[:body], "6 de septiembre"
    assert_includes item[:body], "superior a tu promedio diario"
  end

  test "exceptional spending is not reported for ordinary variation" do
    range = Date.new(2026, 9, 1)..Date.new(2026, 9, 10)
    trend = trend_for(range, {
      Date.new(2026, 9, 2) => 100_000,
      Date.new(2026, 9, 3) => 110_000,
      Date.new(2026, 9, 4) => 90_000,
      Date.new(2026, 9, 5) => 100_000
    })

    refute insight(trend, :exceptional)[:available]
  end

  test "patterns compare weekend and weekday daily averages" do
    range = Date.new(2026, 9, 1)..Date.new(2026, 9, 14)
    totals = {}
    [ Date.new(2026, 9, 5), Date.new(2026, 9, 6) ].each { |date| totals[date] = 300_000 }
    [ Date.new(2026, 9, 2), Date.new(2026, 9, 4), Date.new(2026, 9, 9), Date.new(2026, 9, 11) ]
      .each { |date| totals[date] = 10_000 }
    trend = trend_for(range, totals)

    item = insight(trend, :patterns)

    assert item[:available]
    assert_includes item[:body], "fines de semana"
  end

  test "patterns stay neutral without a full weekend sample" do
    range = Date.new(2026, 9, 1)..Date.new(2026, 9, 4)
    trend = trend_for(range, { Date.new(2026, 9, 2) => 100_000 })

    refute insight(trend, :patterns)[:available]
  end

  test "all insights are neutral when there is no spending" do
    range = Date.new(2026, 9, 1)..Date.new(2026, 9, 10)
    data = Reports::SpendingTrendInsights.new(trend: trend_for(range, {})).call

    assert data[:insufficient]
    assert data[:items].none? { |item| item[:available] }
    assert_equal 3, data[:items].size
  end
end
