# frozen_string_literal: true

require "test_helper"

class Loans::AccrualCycleTest < ActiveSupport::TestCase
  def cycle(reference_day: 11, calculation_date: Date.new(2026, 11, 20), start_date: nil)
    Loans::AccrualCycle.new(reference_day: reference_day, calculation_date: calculation_date,
                            start_date: start_date)
  end

  test "resolves the current cycle from the reference day" do
    result = cycle

    assert result.available?
    assert_equal Date.new(2026, 11, 11), result.cycle_start_date
    assert_equal Date.new(2026, 12, 11), result.next_cycle_date
    assert_equal 30, result.cycle_days
    assert_equal 9, result.elapsed_days
  end

  test "before the reference day the previous month's cycle is used" do
    result = cycle(calculation_date: Date.new(2026, 11, 5))

    assert_equal Date.new(2026, 10, 11), result.cycle_start_date
    assert_equal Date.new(2026, 11, 11), result.next_cycle_date
    assert_equal 31, result.cycle_days
    assert_equal 25, result.elapsed_days
  end

  test "on the reference day the elapsed days are zero" do
    result = cycle(calculation_date: Date.new(2026, 11, 11))

    assert_equal Date.new(2026, 11, 11), result.cycle_start_date
    assert_equal 0, result.elapsed_days
  end

  test "day 31 is treated as day 30" do
    result = cycle(reference_day: 31, calculation_date: Date.new(2026, 1, 31))

    assert_equal Date.new(2026, 1, 30), result.cycle_start_date
    assert_equal Date.new(2026, 2, 28), result.next_cycle_date
    assert_equal 29, result.cycle_days
  end

  test "a month without the reference day uses its last day" do
    result = cycle(reference_day: 30, calculation_date: Date.new(2026, 2, 27))

    assert_equal Date.new(2026, 1, 30), result.cycle_start_date
    assert_equal Date.new(2026, 2, 28), result.next_cycle_date
  end

  test "leap February uses its real last day" do
    result = cycle(reference_day: 30, calculation_date: Date.new(2024, 2, 29))

    assert_equal Date.new(2024, 2, 29), result.cycle_start_date
    assert_equal Date.new(2024, 3, 30), result.next_cycle_date
  end

  test "a loan start date later than the cycle start prorates the first cycle" do
    result = cycle(start_date: Date.new(2026, 11, 15))

    assert_equal Date.new(2026, 11, 11), result.cycle_start_date
    assert_equal Date.new(2026, 11, 15), result.accrual_start_date
    assert_equal 5, result.elapsed_days
    assert_equal 30, result.cycle_days
    refute result.before_loan_start?
  end

  test "a calculation before the loan start is flagged" do
    result = cycle(calculation_date: Date.new(2026, 11, 20), start_date: Date.new(2026, 12, 1))

    assert result.before_loan_start?
  end

  test "an invalid or missing reference day is unavailable" do
    refute cycle(reference_day: nil).available?
    refute cycle(reference_day: 0).available?
    refute cycle(reference_day: 32).available?
  end
end
