# frozen_string_literal: true

module Gmf
  # Gmf::Period
  # Determines the GMF accounting period (calendar month) for a given date.
  # GMF periods are ALWAYS calendar months, independent of the user's
  # financial cycle (PayCycle). Retroactive movements affect the calendar
  # month of their own date.
  #
  # Methods: .for(date), .range(year, month)
  #
  # Example: Gmf::Period.for(Date.new(2026, 11, 15)) # => { year: 2026, month: 11 }
  module Period
    def self.for(date)
      date = date.to_date
      { year: date.year, month: date.month }
    end

    def self.range(year, month)
      Date.new(year, month, 1).beginning_of_month..Date.new(year, month, 1).end_of_month
    end
  end
end
