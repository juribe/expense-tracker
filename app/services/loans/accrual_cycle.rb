# frozen_string_literal: true

# Loans::AccrualCycle
# Resolves the monthly interest cycle for a loan from a reference day of the
# month. Days 29-31 are capped at 30 and, when the month is shorter, clamped
# to its last actual day. The cycle length is the real number of days between
# consecutive reference dates, so a complete cycle can accrue one full
# monthly rate.
#
# Example: Loans::AccrualCycle.new(reference_day: 11, calculation_date:
#   Date.new(2026, 11, 20)).cycle_start_date # => 2026-11-11
class Loans::AccrualCycle
  MAX_REFERENCE_DAY = 30

  attr_reader :reference_day, :calculation_date, :start_date

  def initialize(reference_day:, calculation_date: Date.current, start_date: nil)
    @reference_day = reference_day
    @calculation_date = parse_date(calculation_date)
    @start_date = parse_date(start_date)
  end

  def available?
    reference_day.to_i.between?(1, 31) && calculation_date.present?
  end

  def cycle_start_date
    return nil unless available?

    @cycle_start_date ||= begin
      candidate = date_in_month(calculation_date.year, calculation_date.month)
      if candidate > calculation_date
        previous_month = calculation_date << 1
        candidate = date_in_month(previous_month.year, previous_month.month)
      end
      candidate
    end
  end

  def next_cycle_date
    return nil unless cycle_start_date

    @next_cycle_date ||= begin
      candidate = date_in_month(cycle_start_date.year, cycle_start_date.month)
      candidate = (cycle_start_date >> 1).then { |date| date_in_month(date.year, date.month) } unless candidate > cycle_start_date
      candidate
    end
  end

  def cycle_days
    return nil unless cycle_start_date && next_cycle_date

    (next_cycle_date - cycle_start_date).to_i
  end

  # The loan cannot accrue before its first payment date, so a cycle that
  # started earlier uses the later date for the elapsed-day count while the
  # full cycle length keeps the monthly-rate proportion.
  def accrual_start_date
    return cycle_start_date if cycle_start_date.nil? || start_date.nil?

    [ cycle_start_date, start_date ].max
  end

  def elapsed_days
    return 0 unless accrual_start_date && calculation_date
    return 0 if calculation_date < accrual_start_date

    (calculation_date - accrual_start_date).to_i
  end

  def before_loan_start?
    accrual_start_date.present? && calculation_date.present? && calculation_date < accrual_start_date
  end

  def effective_reference_day
    [ reference_day.to_i, MAX_REFERENCE_DAY ].min
  end

  private

  def date_in_month(year, month)
    last_day = Date.new(year, month, -1).day
    Date.new(year, month, [ effective_reference_day, last_day ].min)
  end

  def parse_date(value)
    return nil if value.blank?

    value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
  rescue Date::Error, TypeError
    nil
  end
end
