# frozen_string_literal: true

require "test_helper"

class ReportsPeriodTest < ActiveSupport::TestCase
  setup do
    @anchor = Date.new(2026, 9, 15)
  end

  def period(preset, start_date: nil, end_date: nil, date: @anchor)
    Reports::Period.new(preset: preset, date: date, start_date: start_date, end_date: end_date)
  end

  test "this month covers the full reference month" do
    p = period("this_month")

    assert_equal Date.new(2026, 9, 1)..Date.new(2026, 9, 30), p.range
    assert_equal Date.new(2026, 8, 1)..Date.new(2026, 8, 31), p.previous_range
    assert_equal :day, p.bucket
  end

  test "last month and its previous equivalent" do
    p = period("last_month")

    assert_equal Date.new(2026, 8, 1)..Date.new(2026, 8, 31), p.range
    assert_equal Date.new(2026, 7, 1)..Date.new(2026, 7, 31), p.previous_range
  end

  test "last 3 months are the three months ending with the reference month" do
    p = period("last_3_months")

    assert_equal Date.new(2026, 7, 1)..Date.new(2026, 9, 30), p.range
    assert_equal Date.new(2026, 4, 1)..Date.new(2026, 6, 30), p.previous_range
    assert_equal :week, p.bucket
  end

  test "last 6 months use a month bucket" do
    p = period("last_6_months")

    assert_equal Date.new(2026, 4, 1)..Date.new(2026, 9, 30), p.range
    assert_equal Date.new(2025, 10, 1)..Date.new(2026, 3, 31), p.previous_range
    assert_equal :week, p.bucket
  end

  test "last 12 months use a month bucket" do
    p = period("last_12_months")

    assert_equal Date.new(2025, 10, 1)..Date.new(2026, 9, 30), p.range
    assert_equal Date.new(2024, 10, 1)..Date.new(2025, 9, 30), p.previous_range
    assert_equal :month, p.bucket
  end

  test "this year compares against the full previous year" do
    p = period("this_year")

    assert_equal Date.new(2026, 1, 1)..Date.new(2026, 12, 31), p.range
    assert_equal Date.new(2025, 1, 1)..Date.new(2025, 12, 31), p.previous_range
    assert_equal :month, p.bucket
  end

  test "custom range compares against the immediately preceding window of equal length" do
    p = period("custom", start_date: Date.new(2026, 3, 10), end_date: Date.new(2026, 3, 19))

    assert_equal Date.new(2026, 3, 10)..Date.new(2026, 3, 19), p.range
    assert_equal Date.new(2026, 2, 28)..Date.new(2026, 3, 9), p.previous_range
    assert_equal :day, p.bucket
  end

  test "custom range spans month boundaries for previous window" do
    p = period("custom", start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31))

    assert_equal Date.new(2026, 2, 1)..Date.new(2026, 2, 28), p.previous_range
  end

  test "unknown preset falls back to this month" do
    p = period("nonsense")

    assert_equal Date.new(2026, 9, 1)..Date.new(2026, 9, 30), p.range
  end

  test "custom without dates falls back to this month" do
    p = period("custom")

    assert_equal Date.new(2026, 9, 1)..Date.new(2026, 9, 30), p.range
  end

  test "preset is normalized and exposed" do
    assert_equal "this_month", period("this_month").preset
    assert_equal "this_month", period("unknown").preset
    assert_equal "custom", period("custom", start_date: @anchor, end_date: @anchor).preset
  end

  test "labels use the locale names for presets" do
    assert_equal "Sep 2026", period("this_month").label
    assert_equal "Ago 2026", period("last_month").label
    assert_equal "Jul–Sep 2026", period("last_3_months").label
    assert_equal "10/03/2026 – 19/03/2026", period("custom", start_date: Date.new(2026, 3, 10), end_date: Date.new(2026, 3, 19)).label
  end

  test "cycle presets with a configured schedule" do
    user = User.create!(name: "Cycle User", email: "cycle_period_test@example.com", password: "password123")
    user.update!(financial_cycle_start_day: 20)

    p = Reports::Period.new(preset: "this_month", date: Date.new(2026, 10, 25), user: user)

    assert_equal "this_cycle", p.preset
    assert_equal Date.new(2026, 10, 20)..Date.new(2026, 11, 19), p.range
    assert_equal Date.new(2026, 9, 20)..Date.new(2026, 10, 19), p.previous_range
    assert_equal :day, p.bucket
  end

  test "last month becomes the previous cycle with a configured schedule" do
    user = User.create!(name: "Cycle User", email: "cycle_period_last_test@example.com", password: "password123")
    user.update!(financial_cycle_start_day: 20)

    p = Reports::Period.new(preset: "last_month", date: Date.new(2026, 10, 25), user: user)

    assert_equal "last_cycle", p.preset
    assert_equal Date.new(2026, 9, 20)..Date.new(2026, 10, 19), p.range
    assert_equal Date.new(2026, 8, 20)..Date.new(2026, 9, 19), p.previous_range
  end

  test "last 3 months become three cycles with a configured schedule" do
    user = User.create!(name: "Cycle User", email: "cycle_period_span_test@example.com", password: "password123")
    user.update!(financial_cycle_start_day: 20)

    p = Reports::Period.new(preset: "last_3_months", date: Date.new(2026, 10, 25), user: user)

    assert_equal "last_3_cycles", p.preset
    assert_equal Date.new(2026, 8, 20)..Date.new(2026, 11, 19), p.range
    assert_equal Date.new(2026, 5, 20)..Date.new(2026, 8, 19), p.previous_range
    assert_equal :week, p.bucket
  end

  test "month presets stay calendar with a default calendar schedule" do
    user = User.create!(name: "Calendar User", email: "cycle_period_calendar_test@example.com", password: "password123")

    p = Reports::Period.new(preset: "this_month", date: Date.new(2026, 10, 25), user: user)

    assert_equal "this_month", p.preset
    assert_equal Date.new(2026, 10, 1)..Date.new(2026, 10, 31), p.range
  end

  test "cycle presets degrade to months without a configured schedule" do
    p = period("this_cycle", date: @anchor)

    assert_equal "this_month", p.preset
    assert_equal Date.new(2026, 9, 1)..Date.new(2026, 9, 30), p.range
  end

  test "this cycle label names the payday month" do
    user = User.create!(name: "Cycle User", email: "cycle_period_label_test@example.com", password: "password123")
    user.update!(financial_cycle_start_day: 20)

    p = Reports::Period.new(preset: "this_month", date: Date.new(2026, 10, 25), user: user)

    assert_match(/oct/i, p.label)
    assert_match(/2026/, p.label)
  end
end
