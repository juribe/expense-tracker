# frozen_string_literal: true

module ExpenseResolver
  class DateResult
    Result = Struct.new(:date) do
    end

    attr_accessor :expense, :today, :allow_heuristic

    def self.call(expense:, today: Date.current, allow_heuristic: true)
      new(expense: expense, today: today, allow_heuristic: allow_heuristic).call
    end

    def initialize(expense:, today:, allow_heuristic: true)
      self.expense = expense
      self.today = today
      self.allow_heuristic = allow_heuristic
    end

    def call
      Result.new(date)
    end

    private

    def date
      heuristic = allow_heuristic ? heuristic_date : nil
      return heuristic if heuristic && trusted?(heuristic)

      ai_date || heuristic
    end

    # A fragment mentioning several distinct dates (or shared across entries)
    # is ambiguous: the heuristic resolution may belong to another expense.
    # The AI date wins there; single-date fragments keep the heuristic guard.
    def trusted?(heuristic)
      return true if ai_date.nil?
      return true if heuristic == ai_date

      ExpenseResolver::Dates::Service.scan_dates(expense.original_text, today: today).one?
    end

    def heuristic_date
      result = ExpenseResolver::Dates::Service.detect_date(expense.original_text, today: today)
      result&.first
    end

    def ai_date
      ExpenseResolver::Dates::Service.parse_iso_date(expense.date)
    end
  end
end
