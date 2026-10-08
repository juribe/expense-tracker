# frozen_string_literal: true

module Credits
  module Amortization
    # Result
    # Outcome of building an amortization schedule: every generated row plus
    # aggregated future costs, termination facts (payoff date, truncation
    # reason) and comparators used by the credit simulators.
    Result = Struct.new(
      :rows, :truncated, :reason, :extra_cash, :final_balance,
      keyword_init: true
    ) do
      def truncated?
        truncated
      end

      def installments
        rows.size
      end

      def last_installment_number
        rows.last&.installment_number
      end

      def payoff_date
        rows.last&.date
      end

      def future_interest
        sum_rows(:interest)
      end

      def future_principal
        sum_rows(:principal)
      end

      def future_insurance
        sum_rows(:insurance)
      end

      def future_other
        sum_rows(:other)
      end

      def future_total
        sum_rows(:total_payment)
      end

      def interest_saved_against(other_interest)
        (other_interest.to_d - future_interest).round(2)
      end

      private

      def sum_rows(key)
        rows.reduce(0.to_d) { |total, row| total + row[key].to_d }
      end
    end
  end
end
