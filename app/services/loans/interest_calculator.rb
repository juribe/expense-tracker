# frozen_string_literal: true

# Loans::InterestCalculator
# Estimates the interest accrued on a loan principal during one monthly cycle.
# The daily rate is derived from the complete cycle length so that a full
# cycle produces the equivalent monthly rate; a partial cycle is prorated.
# Informational only: it never writes principal, transactions or reconciliation.
#
# Example: Loans::InterestCalculator.call(
#   principal_balance: "67.166.819,12", interest_rate: "18.05",
#   interest_rate_type: "effective_annual",
#   cycle_start_date: Date.new(2026, 11, 11),
#   next_cycle_date: Date.new(2026, 12, 11),
#   calculation_date: Date.new(2026, 11, 20)
# )
class Loans::InterestCalculator
  SUPPORTED_RATE_TYPES = %w[effective_annual nominal_annual monthly].freeze
  MONTHS_PER_YEAR = BigDecimal("12")
  PERCENT = BigDecimal("100")
  MONEY_DECIMALS = 2
  ROUNDING_MODE = BigDecimal::ROUND_HALF_UP

  Result = Struct.new(
    :estimated_interest, :estimated_total_balance, :elapsed_days, :daily_rate,
    :principal_balance, :cycle_start_date, :next_cycle_date, :accrual_start_date,
    :cycle_days, :rate_type, :status, keyword_init: true
  ) do
    def calculated?
      status == :ok
    end

    def paid_in_cycle?
      status == :paid_in_cycle
    end

    def displayable?
      calculated? || paid_in_cycle?
    end

    def available?
      calculated?
    end

    def unavailable?
      !displayable?
    end

    alias interest estimated_interest
    alias total_balance estimated_total_balance
    alias days elapsed_days
    alias reference_date cycle_start_date
  end

  class << self
    def call(principal_balance:, interest_rate:, interest_rate_type:, cycle_start_date:,
             next_cycle_date:, calculation_date: Date.current, accrual_start_date: nil)
      new(
        principal_balance: principal_balance,
        interest_rate: interest_rate,
        interest_rate_type: interest_rate_type,
        cycle_start_date: cycle_start_date,
        next_cycle_date: next_cycle_date,
        calculation_date: calculation_date,
        accrual_start_date: accrual_start_date
      ).call
    end

    alias calculate call

    def paid_in_cycle(principal_balance:, cycle_start_date:, next_cycle_date:,
                      calculation_date: Date.current, accrual_start_date: nil)
      principal = parse_decimal(principal_balance)
      cycle_days = date_distance(cycle_start_date, next_cycle_date)
      accrual_start = parse_date(accrual_start_date) || parse_date(cycle_start_date)
      calculation = parse_date(calculation_date)
      elapsed = if accrual_start && calculation && calculation >= accrual_start
        (calculation - accrual_start).to_i
      else
        0
      end

      Result.new(
        estimated_interest: BigDecimal("0"),
        estimated_total_balance: principal,
        elapsed_days: elapsed,
        principal_balance: principal,
        cycle_start_date: parse_date(cycle_start_date),
        next_cycle_date: parse_date(next_cycle_date),
        accrual_start_date: accrual_start,
        cycle_days: cycle_days,
        status: :paid_in_cycle
      )
    end

    def unavailable(status)
      Result.new(status: status)
    end

    private

    def parse_decimal(value)
      return nil if value.blank?

      BigDecimal(MoneyFormat.normalize(value).to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def date_distance(start_date, end_date)
      start = parse_date(start_date)
      finish = parse_date(end_date)
      return nil if start.nil? || finish.nil?

      (finish - start).to_i
    end

    def parse_date(value)
      return nil if value.blank?

      value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
    rescue Date::Error, TypeError
      nil
    end
  end

  def initialize(principal_balance:, interest_rate:, interest_rate_type:, cycle_start_date:,
                 next_cycle_date:, calculation_date:, accrual_start_date: nil)
    @principal = decimal(principal_balance)
    @rate = decimal(interest_rate)
    @rate_type = interest_rate_type.to_s.presence
    @cycle_start_date = parse_date(cycle_start_date)
    @next_cycle_date = parse_date(next_cycle_date)
    @calculation_date = parse_date(calculation_date)
    @accrual_start_date = parse_date(accrual_start_date) || @cycle_start_date
  end

  def call
    return self.class.unavailable(:missing_principal) if @principal.nil?
    return self.class.unavailable(:missing_rate) if @rate.nil?
    return self.class.unavailable(:missing_rate_type) if @rate_type.nil?
    return self.class.unavailable(:unsupported_rate_type) unless SUPPORTED_RATE_TYPES.include?(@rate_type)
    return self.class.unavailable(:missing_cycle) if @cycle_start_date.nil? || @next_cycle_date.nil? || @calculation_date.nil?

    cycle_days = (@next_cycle_date - @cycle_start_date).to_i
    return self.class.unavailable(:invalid_cycle) unless cycle_days.positive?
    return self.class.unavailable(:negative_period) if @calculation_date < @cycle_start_date

    elapsed_days = [ (@calculation_date - @accrual_start_date).to_i, 0 ].max
    interest = round_money(accrued_interest(elapsed_days, cycle_days))
    Result.new(
      estimated_interest: interest,
      estimated_total_balance: round_money(@principal + interest),
      elapsed_days: elapsed_days,
      daily_rate: daily_rate(cycle_days),
      principal_balance: @principal,
      cycle_start_date: @cycle_start_date,
      next_cycle_date: @next_cycle_date,
      accrual_start_date: @accrual_start_date,
      cycle_days: cycle_days,
      rate_type: @rate_type,
      status: :ok
    )
  end

  private

  def accrued_interest(days, cycle_days)
    return BigDecimal("0") if days.zero? || @rate.zero?

    if nominal_annual?
      @principal * monthly_rate * BigDecimal(days) / BigDecimal(cycle_days)
    else
      daily_factor = (1 + monthly_rate)**(BigDecimal("1") / BigDecimal(cycle_days))
      @principal * ((daily_factor**BigDecimal(days)) - 1)
    end
  end

  def daily_rate(cycle_days)
    return monthly_rate / BigDecimal(cycle_days) if nominal_annual?

    ((1 + monthly_rate)**(BigDecimal("1") / BigDecimal(cycle_days))) - 1
  end

  def monthly_rate
    @monthly_rate ||= case @rate_type
    when "effective_annual"
      ((1 + (@rate / PERCENT))**(BigDecimal("1") / MONTHS_PER_YEAR)) - 1
    when "monthly"
      @rate / PERCENT
    when "nominal_annual"
      @rate / PERCENT / MONTHS_PER_YEAR
    end
  end

  def nominal_annual?
    @rate_type == "nominal_annual"
  end

  def decimal(value)
    return nil if value.blank?

    BigDecimal(MoneyFormat.normalize(value).to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_date(value)
    return nil if value.blank?

    value.respond_to?(:to_date) ? value.to_date : Date.parse(value.to_s)
  rescue Date::Error, TypeError
    nil
  end

  def round_money(value)
    value.to_d.round(MONEY_DECIMALS, ROUNDING_MODE)
  end
end
