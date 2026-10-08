# frozen_string_literal: true

require "test_helper"

# Credits::Rate::PeriodConverter converts the credit's annual interest rate
# (EA, nominal or monthly) into the periodic rate used by the amortization
# engine, rounded to 12 decimals for determinism.
class PeriodConverterTest < ActiveSupport::TestCase
  test "monthly rate type is used as-is per period" do
    rate = Credits::Rate::PeriodConverter.call(rate: "1.0", rate_type: "monthly", frequency: "monthly")

    assert_equal BigDecimal("0.01"), rate
  end

  test "effective annual rate converts to the equivalent monthly rate" do
    rate = Credits::Rate::PeriodConverter.call(rate: "12.682503013196", rate_type: "effective_annual", frequency: "monthly")

    assert_equal BigDecimal("0.01"), rate
  end

  test "nominal annual rate divides by the periods per year" do
    rate = Credits::Rate::PeriodConverter.call(rate: "12", rate_type: "nominal_annual", frequency: "monthly")

    assert_equal BigDecimal("0.01"), rate
  end

  test "effective annual rate converts per frequency" do
    biweekly = Credits::Rate::PeriodConverter.call(rate: "22.89", rate_type: "effective_annual", frequency: "biweekly")
    expected = ((1 + 0.2289)**(1.0 / 26) - 1).round(12)

    assert_in_delta expected, biweekly.to_f, 1e-11
  end

  test "nominal quarterly rate divides by four" do
    rate = Credits::Rate::PeriodConverter.call(rate: "8", rate_type: "nominal_annual", frequency: "quarterly")

    assert_equal BigDecimal("0.02"), rate
  end

  test "a monthly rate type applies compounding across a quarterly frequency" do
    rate = Credits::Rate::PeriodConverter.call(rate: "1.0", rate_type: "monthly", frequency: "quarterly")

    assert_in_delta 0.030301, rate.to_f, 1e-12
  end

  test "zero rate stays zero" do
    rate = Credits::Rate::PeriodConverter.call(rate: "0", rate_type: "effective_annual", frequency: "monthly")

    assert_equal BigDecimal("0"), rate
  end

  test "unknown frequency raises" do
    assert_raises(ArgumentError) do
      Credits::Rate::PeriodConverter.call(rate: "1.0", rate_type: "monthly", frequency: "yearly")
    end
  end
end
