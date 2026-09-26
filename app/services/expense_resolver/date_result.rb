# frozen_string_literal: true

module ExpenseResolver
  class DateResult
    Result = Struct.new(:date) do
    end

    attr_accessor :expense, :today, :allow_heuristic, :full_text

    def self.call(expense:, today: Date.current, allow_heuristic: true, full_text: nil)
      new(expense: expense, today: today, allow_heuristic: allow_heuristic, full_text: full_text).call
    end

    def initialize(expense:, today:, allow_heuristic: true, full_text: nil)
      self.expense = expense
      self.today = today
      self.allow_heuristic = allow_heuristic
      self.full_text = full_text
    end

    def call
      Result.new(date)
    end

    private

    def date
      heuristic = allow_heuristic ? heuristic_date : nil
      return heuristic if heuristic && trusted?(heuristic)

      if fragment_dates.empty?
        # The fragment carries no date expression: the deterministic reading
        # of the full message outranks the model's own resolution.
        return full_text_date || ai_date || heuristic
      end

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

    # When the fragment dropped the date expression entirely, the model's date
    # is its own (unreliable) reading of the full message. When the message
    # resolves to exactly one distinct date, the deterministic resolution of
    # that expression is authoritative over the AI date.
    def full_text_date
      return nil if full_text.blank?
      return nil unless fragment_dates.empty?

      dates = ExpenseResolver::Dates::Service.scan_dates(
        ExpenseResolver::Text::Service.normalize_text(full_text), today: today
      )
      dates.one? ? dates.first : nil
    end

    def fragment_dates
      @fragment_dates ||= ExpenseResolver::Dates::Service.scan_dates(expense.original_text, today: today)
    end
  end
end
