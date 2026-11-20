# frozen_string_literal: true

require "test_helper"

class Loans::InterestCalculatorTest < ActiveSupport::TestCase
  CYCLE_START = Date.new(2026, 11, 11)
  NEXT_CYCLE = Date.new(2026, 12, 11)

  def calculate(**overrides)
    Loans::InterestCalculator.call(
      principal_balance: "1.000.000",
      interest_rate: "18.05",
      interest_rate_type: "effective_annual",
      cycle_start_date: CYCLE_START,
      next_cycle_date: NEXT_CYCLE,
      calculation_date: Date.new(2026, 11, 20),
      **overrides
    )
  end

  test "uses the complete cycle to derive the daily rate" do
    result = calculate

    assert result.calculated?
    assert_equal 30, result.cycle_days
    assert_equal 9, result.elapsed_days
    assert_equal BigDecimal("4157.07"), result.estimated_interest
    assert_equal BigDecimal("1004157.07"), result.estimated_total_balance
  end

  test "a complete cycle equals the monthly equivalent rate" do
    result = calculate(calculation_date: NEXT_CYCLE)

    assert_equal 30, result.elapsed_days
    assert_equal BigDecimal("13924.22"), result.estimated_interest
  end

  test "a 31-day cycle still produces the same complete monthly interest" do
    result = calculate(
      cycle_start_date: Date.new(2026, 12, 11),
      next_cycle_date: Date.new(2027, 1, 11),
      calculation_date: Date.new(2027, 1, 11)
    )

    assert_equal 31, result.cycle_days
    assert_equal BigDecimal("13924.22"), result.estimated_interest
  end

  test "different elapsed periods accrue proportionally more interest" do
    nine_days = calculate
    twenty_days = calculate(calculation_date: Date.new(2026, 11, 30))

    assert_operator twenty_days.estimated_interest, :>, nine_days.estimated_interest
  end

  test "zero elapsed days returns zero interest" do
    result = calculate(calculation_date: CYCLE_START)

    assert result.calculated?
    assert_equal 0, result.elapsed_days
    assert_equal BigDecimal("0"), result.estimated_interest
    assert_equal BigDecimal("1000000"), result.estimated_total_balance
  end

  test "zero interest rate returns zero interest without failing" do
    result = calculate(interest_rate: "0")

    assert result.calculated?
    assert_equal BigDecimal("0"), result.estimated_interest
  end

  test "missing cycle dates are unavailable" do
    assert_equal :missing_cycle, calculate(cycle_start_date: nil).status
    assert_equal :missing_cycle, calculate(next_cycle_date: nil).status
  end

  test "an invalid cycle is rejected" do
    result = calculate(next_cycle_date: CYCLE_START)

    assert result.unavailable?
    assert_equal :invalid_cycle, result.status
  end

  test "negative elapsed periods are not calculated" do
    result = calculate(calculation_date: Date.new(2026, 11, 1))

    assert result.unavailable?
    assert_equal :negative_period, result.status
  end

  test "missing rate or rate type is unavailable" do
    assert_equal :missing_rate, calculate(interest_rate: nil).status
    assert_equal :missing_rate_type, calculate(interest_rate_type: nil).status
  end

  test "unknown rate types are not interpreted as another convention" do
    result = calculate(interest_rate_type: "weekly_effective")

    assert result.unavailable?
    assert_equal :unsupported_rate_type, result.status
    assert_nil result.estimated_interest
  end

  test "monthly rates use a monthly effective conversion" do
    result = calculate(interest_rate: "2", interest_rate_type: "monthly")

    assert result.calculated?
    assert_equal BigDecimal("5958.47"), result.estimated_interest
  end

  test "nominal annual rates use a simple monthly conversion" do
    result = calculate(interest_rate_type: "nominal_annual")

    assert result.calculated?
    assert_equal BigDecimal("4512.50"), result.estimated_interest
  end

  test "leap-year cycles use their real length and still complete the monthly rate" do
    result = calculate(
      cycle_start_date: Date.new(2024, 2, 11),
      next_cycle_date: Date.new(2024, 3, 11),
      calculation_date: Date.new(2024, 3, 11)
    )

    assert_equal 29, result.cycle_days
    assert_equal BigDecimal("13924.22"), result.estimated_interest
  end

  test "accrual can start later than the reference date for a new loan" do
    result = calculate(accrual_start_date: Date.new(2026, 11, 15))

    assert_equal 5, result.elapsed_days
    assert_equal 30, result.cycle_days
    assert_operator result.estimated_interest, :<, calculate.estimated_interest * 2
  end

  test "rounds monetary results to two decimals" do
    result = calculate(calculation_date: Date.new(2026, 11, 12))

    assert_equal BigDecimal("461.05"), result.estimated_interest
  end

  test "paid-in-cycle result is displayable with zero interest" do
    result = Loans::InterestCalculator.paid_in_cycle(
      principal_balance: "1.000.000",
      cycle_start_date: CYCLE_START,
      next_cycle_date: NEXT_CYCLE,
      calculation_date: Date.new(2026, 11, 20)
    )

    assert result.paid_in_cycle?
    assert result.displayable?
    assert_equal BigDecimal("0"), result.estimated_interest
    assert_equal BigDecimal("1000000"), result.estimated_total_balance
  end
end
