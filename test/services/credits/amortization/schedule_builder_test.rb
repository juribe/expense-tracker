# frozen_string_literal: true

require "test_helper"

# Reference loan used across the amortization tests:
#   balance $1,200 · installment $300 · monthly interest rate 1%
# Expected ledger (interest rounded to cents each period):
#   1: interest 12.00 principal 288.00 closing 912.00
#   2: interest  9.12 principal 290.88 closing 621.12
#   3: interest  6.21 principal 293.79 closing 327.33
#   4: interest  3.27 principal 296.73 closing  30.60
#   5: interest  0.31 final    30.60 closing   0.00  (total 30.91)
# Total interest: 30.91 → 5 installments
class ScheduleBuilderTest < ActiveSupport::TestCase
  REFERENCE = {
    balance: "1200.00", installment_amount: "300.00", monthly_rate: "1.0",
    frequency: "monthly", first_date: Date.new(2026, 1, 5)
  }.freeze

  test "builds the standard fixed-rate schedule with exact cents" do
    result = build_reference_lock

    rows = result.rows
    assert_equal 5, rows.size

    first = rows[0]
    assert_equal 1, first.installment_number
    assert_equal BigDecimal("1200.00"), first.opening_balance
    assert_equal BigDecimal("12.00"), first.interest
    assert_equal BigDecimal("288.00"), first.principal
    assert_equal BigDecimal("300.00"), first.total_payment
    assert_equal BigDecimal("912.00"), first.closing_balance

    assert_equal BigDecimal("290.88"), rows[1].principal
    assert_equal BigDecimal("293.79"), rows[2].principal
    assert_equal BigDecimal("296.73"), rows[3].principal

    last = rows[4]
    assert_equal BigDecimal("0.31"), last.interest
    assert_equal BigDecimal("30.60"), last.principal
    assert_equal BigDecimal("30.91"), last.total_payment
    assert_equal BigDecimal("0"), last.closing_balance

    assert_equal Date.new(2026, 5, 5), last.date
  end

  test "totals a reference loan's interest, principal and installment count" do
    result = build_reference_lock

    assert_equal BigDecimal("30.91"), result.future_interest
    assert_equal BigDecimal("1200.00"), result.future_principal
    assert_equal BigDecimal("0"), result.future_insurance
    assert_equal BigDecimal("0"), result.future_other
    assert_equal 5, result.installments
    assert_not result.truncated?
    assert_nil result.reason
  end

  test "rows are fully amortizing: closing balance of row N is opening balance of row N+1" do
    rows = build_reference_lock.rows

    rows.each_cons(2) do |row, next_row|
      assert_equal row.closing_balance, next_row.opening_balance
    end
  end

  test "handles insurance and other recurring charges" do
    result = Credits::Amortization::ScheduleBuilder.build(
      balance: BigDecimal("1000.00"),
      periodic_rate: BigDecimal("0"),
      installment_amount: BigDecimal("120.00"),
      insurance: BigDecimal("10.00"),
      other: BigDecimal("2.00"),
      start_installment_number: 1,
      first_payment_date: Date.new(2026, 1, 10),
      frequency: "monthly"
    )

    rows = result.rows
    assert_equal 10, rows.size
    rows.take(9).each do |row|
      assert_equal BigDecimal("108.00"), row.principal
      assert_equal BigDecimal("120.00"), row.total_payment
      assert_equal BigDecimal("10.00"), row.insurance
      assert_equal BigDecimal("2.00"), row.other
    end

    final = rows.last
    assert_equal BigDecimal("28.00"), final.principal
    assert_equal BigDecimal("40.00"), final.total_payment
    assert_equal BigDecimal("0"), final.interest
    assert_equal Date.new(2026, 10, 10), final.date
  end

  test "zero interest pays principal in even parts" do
    result = Credits::Amortization::ScheduleBuilder.build(
      balance: BigDecimal("1000.00"),
      periodic_rate: BigDecimal("0"),
      installment_amount: BigDecimal("120.00"),
      insurance: BigDecimal("10.00"),
      other: BigDecimal("2.00"),
      start_installment_number: 1,
      first_payment_date: Date.new(2026, 1, 10),
      frequency: "monthly"
    )

    assert_equal BigDecimal("0"), result.future_interest
    assert_equal BigDecimal("100.00"), result.future_insurance
    assert_equal BigDecimal("20.00"), result.future_other
  end

  test "a one-time extra principal payment after period 2 shortens and saves interest" do
    result = Credits::Amortization::ScheduleBuilder.build(
      **reference_locked, extras: {
        one_time: { after_period: 2, amount: BigDecimal("300.00") }
      }
    )

    rows = result.rows
    assert_equal 4, rows.size
    assert_equal BigDecimal("621.12"), rows[1].closing_balance
    assert_equal BigDecimal("321.12"), rows[2].opening_balance

    # 3: interest 3.21 principal 296.79 → 24.33
    # 4: interest 0.24 final 24.33 (total 24.57)
    assert_equal BigDecimal("24.57"), result.future_interest
    assert_equal BigDecimal("300.00"), result.extra_cash
    assert_equal BigDecimal("6.34"), result.interest_saved_against(BigDecimal("30.91"))
  end

  test "recurring extra payments every period" do
    result = Credits::Amortization::ScheduleBuilder.build(
      **reference_locked, extras: {
        recurring: { start_period: 1, every_n_periods: 1, amount: BigDecimal("100.00") }
      }
    )

    rows = result.rows
    assert_equal 4, rows.size
    # Expected ledger:
    #   1: interest 12.00 principal 288.00 closing 912.00 → extra → 812.00
    #   2: interest  8.12 principal 291.88 closing 520.12 → extra → 420.12
    #   3: interest  4.20 principal 295.80 closing 124.32 → extra →  24.32
    #   4: interest  0.24 final 24.32 total 24.56
    assert_equal BigDecimal("812.00"), rows[1].opening_balance
    assert_equal BigDecimal("8.12"), rows[1].interest
    assert_equal BigDecimal("291.88"), rows[1].principal
    assert_equal BigDecimal("420.12"), rows[2].opening_balance
    assert_equal BigDecimal("0.24"), rows.last.interest
    assert_equal BigDecimal("24.32"), rows.last.principal
    assert_equal BigDecimal("24.56"), rows.last.total_payment

    assert_equal BigDecimal("24.56"), result.future_interest
    assert_equal BigDecimal("300.00"), result.extra_cash
  end

  test "recurring extra payment every three periods" do
    result = Credits::Amortization::ScheduleBuilder.build(
      **reference_locked, extras: {
        recurring: { start_period: 3, every_n_periods: 3, amount: BigDecimal("300.00") }
      }
    )

    rows = result.rows
    assert_equal 4, rows.size
    assert_equal BigDecimal("327.33"), rows[2].closing_balance
    # after 3: extra 300 → 27.33
    #   4: interest 0.27 final 27.33 total 27.60
    assert_equal BigDecimal("27.33"), rows.last.opening_balance
    assert_equal BigDecimal("0.27"), rows.last.interest
    assert_equal BigDecimal("27.60"), rows.last.total_payment
    assert_equal BigDecimal("300.00"), result.extra_cash
  end

  test "an extra large enough to clear the balance stops the schedule immediately" do
    result = Credits::Amortization::ScheduleBuilder.build(
      **reference_locked, extras: {
        one_time: { after_period: 1, amount: BigDecimal("5000.00") }
      }
    )

    assert_equal 1, result.rows.size
    assert_equal BigDecimal("12.00"), result.future_interest
    # Only the effective balance is applied as extra cash.
    assert_equal BigDecimal("912.00"), result.extra_cash
  end

  test "a very small remaining balance produces a single final mini installment" do
    result = Credits::Amortization::ScheduleBuilder.build(
      balance: BigDecimal("5.00"),
      periodic_rate: BigDecimal("0.01"),
      installment_amount: BigDecimal("300.00"),
      insurance: BigDecimal("0"),
      other: BigDecimal("0"),
      start_installment_number: 13,
      first_payment_date: Date.new(2026, 6, 5),
      frequency: "monthly"
    )

    row = result.rows.last
    assert_equal 1, result.rows.size
    assert_equal 13, row.installment_number
    assert_equal BigDecimal("5.00"), row.principal
    assert_equal BigDecimal("0.05"), row.interest
    assert_equal BigDecimal("5.05"), row.total_payment
  end

  test "an installment below the monthly interest is flagged as truncated" do
    result = Credits::Amortization::ScheduleBuilder.build(
      balance: BigDecimal("1000.00"),
      periodic_rate: BigDecimal("0.01"),
      installment_amount: BigDecimal("9.00"),
      insurance: BigDecimal("0"),
      other: BigDecimal("0"),
      start_installment_number: 1,
      first_payment_date: Date.new(2026, 1, 5),
      frequency: "monthly"
    )

    assert result.truncated?
    assert_equal :installment_never_amortizes, result.reason
    assert_empty result.rows
  end

  test "the schedule is capped at max_installments" do
    result = Credits::Amortization::ScheduleBuilder.build(
      balance: BigDecimal("1000.00"),
      periodic_rate: BigDecimal("0.01"),
      installment_amount: BigDecimal("30.00"),
      insurance: BigDecimal("0"),
      other: BigDecimal("0"),
      start_installment_number: 1,
      first_payment_date: Date.new(2026, 1, 5),
      frequency: "monthly",
      cap: 5
    )

    assert_equal 5, result.rows.size
    assert result.truncated?
    assert_equal :cap_reached, result.reason
  end

  test "dates advance per payment frequency" do
    biweekly = Credits::Amortization::ScheduleBuilder.build(
      balance: BigDecimal("180.00"),
      periodic_rate: BigDecimal("0.01"),
      installment_amount: BigDecimal("80.00"),
      start_installment_number: 1,
      first_payment_date: Date.new(2026, 1, 5),
      frequency: "biweekly"
    )

    # 1: interest 1.80 principal 78.20 → 101.80
    # 2: interest 1.02 principal 78.98 → 22.82
    # 3: interest 0.23 final 22.82 (total 23.05)
    dates = biweekly.rows.map(&:date)
    assert_equal [ Date.new(2026, 1, 5), Date.new(2026, 1, 19), Date.new(2026, 2, 2) ], dates

    quarterly = Credits::Amortization::ScheduleBuilder.build(
      balance: BigDecimal("80.00"),
      periodic_rate: BigDecimal("0"),
      installment_amount: BigDecimal("100.00"),
      start_installment_number: 7,
      first_payment_date: Date.new(2026, 3, 1),
      frequency: "quarterly"
    )

    assert_equal [ Date.new(2026, 3, 1) ], quarterly.rows.map(&:date)
    assert_equal 7, quarterly.rows.first.installment_number
  end

  test "supports multiple one-time extra payments" do
    result = Credits::Amortization::ScheduleBuilder.build(
      **reference_locked,
      extras: {
        one_time: [
          { after_period: 1, amount: BigDecimal("100.00") },
          { after_period: 3, amount: BigDecimal("200.00") }
        ]
      }
    )

    rows = result.rows
    # 1: 12.00/288.00 → 912.00, extra 100 → 812.00
    # 2: 8.12/291.88 → 520.12
    # 3: 5.20/294.80 → 225.32, extra 200 → 25.32
    # 4: 0.25 final 25.32 (total 25.57)
    assert_equal BigDecimal("812.00"), rows[1].opening_balance
    assert_equal BigDecimal("25.32"), rows.last.opening_balance
    assert_equal BigDecimal("0.25"), rows.last.interest
    assert_equal BigDecimal("25.57"), rows.last.total_payment
    assert_equal 4, rows.size
    assert_equal BigDecimal("300.00"), result.extra_cash
  end

  private

  def build_reference_lock
    Credits::Amortization::ScheduleBuilder.build(**reference_locked)
  end

  def reference_locked
    {
      balance: BigDecimal(REFERENCE[:balance]),
      periodic_rate: BigDecimal("0.01"),
      installment_amount: BigDecimal(REFERENCE[:installment_amount]),
      insurance: BigDecimal("0"),
      other: BigDecimal("0"),
      start_installment_number: 1,
      first_payment_date: REFERENCE[:first_date],
      frequency: REFERENCE[:frequency]
    }
  end
end
