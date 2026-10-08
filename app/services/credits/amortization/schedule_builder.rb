# frozen_string_literal: true

module Credits
  module Amortization
    # ScheduleBuilder
    # Deterministic fixed-installment amortization: converts an opening
    # balance plus a periodic rate into the full row ledger until the balance
    # reaches zero, honoring insurance/other recurring charges and extra
    # principal payments (one-time or recurring, applied per period).
    #
    # Money math is BigDecimal throughout; interest is rounded to cents each
    # period. The final installment absorbs the remaining balance so closing
    # balances never go negative.
    #
    # Methods: build
    #
    # Example:
    #   ScheduleBuilder.build(balance: 1_200.to_d, periodic_rate: 0.01.to_d,
    #     installment_amount: 300.to_d, insurance: 10.to_d, other: 2.to_d,
    #     start_installment_number: 13, first_payment_date: Date.current,
    #     frequency: "monthly",
    #     extras: { one_time: { after_period: 2, amount: 300.to_d } })
    class ScheduleBuilder
      DEFAULT_CAP = 720
      CENTS = 2

      def self.build(balance:, periodic_rate:, installment_amount:, frequency:, first_payment_date:,
                     start_installment_number: 1, insurance: 0.to_d, other: 0.to_d,
                     extras: {}, cap: DEFAULT_CAP)
        new(balance, periodic_rate, installment_amount, insurance, other, start_installment_number,
            first_payment_date, frequency, extras, cap).build
      end

      def initialize(balance, periodic_rate, installment_amount, insurance, other,
                     start_installment_number, first_payment_date, frequency, extras, cap)
        @balance = balance.to_d
        @periodic_rate = periodic_rate.to_d
        @installment_amount = installment_amount.to_d
        @insurance = insurance.to_d
        @other = other.to_d
        @start_installment_number = start_installment_number.to_i
        @first_payment_date = first_payment_date
        @frequency = frequency
        @one_time_extra = normalize_one_time(extras[:one_time])
        @recurring_extra = extras[:recurring]
        @cap = cap.to_i.positive? ? cap.to_i : DEFAULT_CAP
      end

      def build
        rows = []
        extra_cash = 0.to_d
        reason = nil

        until @balance <= 0
          if rows.size >= @cap
            reason = :cap_reached
            break
          end

          interest = (@balance * @periodic_rate).round(CENTS)
          principal = @installment_amount - @insurance - @other - interest

          if principal >= @balance
            rows << final_row(interest)
            @balance = 0.to_d
            break
          end

          if principal.negative?
            reason = :installment_never_amortizes
            break
          end

          rows << ordinary_row(interest, principal)
          @balance -= principal

          if (applied = apply_extras(rows.size))
            @balance -= applied
            extra_cash += applied
            break if @balance <= 0
          end
        end

        @balance = 0.to_d if @balance.negative?
        Result.new(rows: rows, truncated: !reason.nil?, reason: reason, extra_cash: extra_cash,
                   final_balance: @balance)
      end

      private

      def ordinary_row(interest, principal)
        date = @first_payment_date
        row = Row.new(
          installment_number: @start_installment_number + rows_count,
          date: date,
          opening_balance: @balance,
          principal: principal,
          interest: interest,
          insurance: @insurance,
          other: @other,
          total_payment: @installment_amount,
          closing_balance: nil,
          projected?: true
        )
        row.closing_balance = (row.opening_balance - principal).round(CENTS)
        @first_payment_date = Period.advance(date, @frequency)
        row
      end

      def final_row(interest)
        row = Row.new(
          installment_number: @start_installment_number + rows_count,
          date: @first_payment_date,
          opening_balance: @balance,
          principal: @balance,
          interest: interest,
          insurance: @insurance,
          other: @other,
          total_payment: @balance + interest + @insurance + @other,
          closing_balance: 0.to_d,
          projected?: true
        )
        @first_payment_date = Period.advance(@first_payment_date, @frequency)
        row
      end

      def apply_extras(period)
        amount = one_time_extra_for(period) || recurring_extra_for(period)
        amount.nil? ? nil : [ amount.round(CENTS), @balance ].min
      end

      def normalize_one_time(one_time)
        return [] if one_time.nil?
        return Array(one_time) if one_time.is_a?(Array)

        [ one_time ]
      end

      def one_time_extra_for(period)
        @one_time_extra.each do |extra|
          after = extra[:after_period].to_i
          return extra[:amount].to_d if after.positive? && period == after
        end
        nil
      end

      def recurring_extra_for(period)
        return nil unless @recurring_extra

        start = @recurring_extra[:start_period].to_i
        every = [ @recurring_extra[:every_n_periods].to_i, 1 ].max
        return nil if period < start || (period - start) % every != 0

        @recurring_extra[:amount].to_d
      end

      def rows_count
        @row_count ||= 0
        @row_count += 1
        @row_count - 1
      end
    end
  end
end
