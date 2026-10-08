# frozen_string_literal: true

module Credits
  module Rate
    # PeriodConverter
    # Converts a credit's annual interest rate into the periodic rate the
    # amortization engine uses, honoring the rate type (effective annual,
    # nominal annual or an already-periodic monthly rate) and the payment
    # frequency. Rounded to 12 decimals for determinism.
    #
    # Methods: call, periods_per_year
    #
    # Example: PeriodConverter.call(rate: "12.6825", rate_type: "effective_annual",
    #                               frequency: "monthly") # => 0.01 BigDecimal
    class PeriodConverter
      MONTHS_PER_FREQUENCY = { "weekly" => nil, "biweekly" => nil, "monthly" => 1, "quarterly" => 3 }.freeze
      PERIODS_PER_YEAR = { "weekly" => 52, "biweekly" => 26, "monthly" => 12, "quarterly" => 4 }.freeze
      RATE_DECIMALS = 12

      def self.call(rate:, rate_type:, frequency:)
        new(rate, rate_type, frequency).call
      end

      def self.periods_per_year(frequency)
        PERIODS_PER_YEAR.fetch(frequency) { raise ArgumentError, "unknown payment frequency: #{frequency}" }
      end

      def initialize(rate, rate_type, frequency)
        @rate = rate.to_d
        @rate_type = rate_type
        @frequency = frequency
        @frequency_periods = PERIODS_PER_YEAR.fetch(frequency) do
          raise ArgumentError, "unknown payment frequency: #{frequency}"
        end
      end

      def call
        (raw_periodic_rate.round(RATE_DECIMALS)).to_d
      end

      private

      def raw_periodic_rate
        case @rate_type
        when "monthly" then periodic_from_monthly
        when "effective_annual" then periodic_from_effective_annual
        when "nominal_annual" then @rate / 100 / @frequency_periods
        else periodic_from_monthly
        end
      end

      def periodic_from_monthly
        # Monthly rates compound across a longer period when the payment
        # frequency skips months (quarterly payments pay 3 months of interest).
        months_per_period = MONTHS_PER_FREQUENCY.fetch(@frequency, 1).to_i
        return @rate / 100 if months_per_period <= 1

        factor = (1 + @rate / 100)**months_per_period
        factor - 1
      end

      def periodic_from_effective_annual
        annual = 1 + @rate / 100
        annual**(1.0 / @frequency_periods) - 1
      end
    end
  end
end
