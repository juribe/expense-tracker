# frozen_string_literal: true

module Mcp
  # NextPaymentDate
  # First occurrence of a configured payment day on or after the reference
  # date, clamped to the month's last day (e.g. day 31 in February).
  #
  # Example: Mcp::NextPaymentDate.for(15) # => Date
  module NextPaymentDate
    module_function

    def for(day, from: Date.current)
      return nil if day.blank?

      candidate = date_in(from.year, from.month, day)
      return candidate if candidate >= from

      following = from.next_month
      date_in(following.year, following.month, day)
    end

    def date_in(year, month, day)
      Date.new(year, month, [ day, Date.new(year, month, -1).day ].min)
    end
  end
end
