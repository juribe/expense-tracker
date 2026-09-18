# frozen_string_literal: true

module ExpenseResolver
  class DateResult
    Result = Struct.new(:date) do
    end

    attr_accessor :expense, :today

    def self.call(expense:, today: Date.current)
      new(expense: expense, today: today).call
    end

    def initialize(expense:, today:)
      self.expense = expense
      self.today = today
    end

    def call
      Result.new(date)
    end

    private

    def date
      heuristic_date || ai_date
    end

    def heuristic_date
      result = ExpenseParser::DateService.detect_date(expense.original_text, today: today)
      result&.first
    end

    def ai_date
      ExpenseParser::DateService.parse_iso_date(expense.date)
    end
  end
end
