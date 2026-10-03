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
end
