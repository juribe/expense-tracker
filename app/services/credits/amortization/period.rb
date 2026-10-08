# frozen_string_literal: true

module Credits
  module Amortization
    # Period
    # Advances a date by one payment period according to the payment
    # frequency. Shared by the schedule builder and the projection builder.
    module Period
      def self.advance(date, frequency)
        case frequency
        when "weekly" then date + 7
        when "biweekly" then date + 14
        when "monthly" then date >> 1
        when "quarterly" then date >> 3
        else raise ArgumentError, "unknown payment frequency: #{frequency}"
        end
      end
    end
  end
end
