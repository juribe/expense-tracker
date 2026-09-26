# frozen_string_literal: true

module ExpenseResolver
  class DateResult
    Result = Struct.new(:date) do
    end

    attr_accessor :expense, :today, :allow_heuristic, :full_text, :entry_position, :entry_count

    def self.call(expense:, today: Date.current, allow_heuristic: true, full_text: nil, entry_position: nil, entry_count: nil)
      new(expense: expense, today: today, allow_heuristic: allow_heuristic,
          full_text: full_text, entry_position: entry_position, entry_count: entry_count).call
    end

    def initialize(expense:, today:, allow_heuristic: true, full_text: nil, entry_position: nil, entry_count: nil)
      self.expense = expense
      self.today = today
      self.allow_heuristic = allow_heuristic
      self.full_text = full_text
      self.entry_position = entry_position
      self.entry_count = entry_count
    end

    def call
      Result.new(date)
    end

    private

    def date
      # Fragment-level date evidence is safe in multi-entry messages too: the
      # fragment's own single date expression is the user's words, and it must
      # outrank the model's date arithmetic ("El viernes" is not a Thursday).
      heuristic = allow_heuristic || fragment_dates.present? ? heuristic_date : nil
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
      return nil if invented_fragment_dates?

      result = ExpenseResolver::Dates::Service.detect_date(expense.original_text, today: today)
      result&.first
    end

    def ai_date
      ExpenseResolver::Dates::Service.parse_iso_date(expense.date)
    end

    # When the fragment dropped the date expression entirely, the model's date
    # is its own (unreliable) reading of the full message. Deterministic rules
    # take over: one expression applies to every entry; several expressions
    # map to entries by text order when the counts match.
    def full_text_date
      return nil if full_text.blank?
      return nil unless fragment_dates.empty?

      dates = ExpenseResolver::Dates::Service.scan_dates(
        ExpenseResolver::Text::Service.normalize_text(full_text), today: today
      )
      return dates.first if dates.one?
      return nil if entry_position.nil? || entry_count.nil? || dates.size != entry_count

      dates[entry_position]
    end

    def fragment_dates
      @fragment_dates ||= begin
        dates = ExpenseResolver::Dates::Service.scan_dates(expense.original_text, today: today)
        invented_fragment_dates? ? [] : dates
      end
    end

    # The model may inject relative words ("hoy") the user never wrote. When
    # every date expression in the fragment is absent from the original
    # message, the fragment's date reading is an invention and is ignored.
    def invented_fragment_dates?
      @invented_fragment_dates ||= begin
        expressions = fragment_expressions
        expressions.present? && full_text.present? &&
          expressions.none? { |word| full_text.match?(word) }
      end
    end

    DATE_EXPRESSION_REGEXPS = [
      /\bhoy\b/i, /\banteayer\b/i, /\bayer\b/i, /la semana pasada/i, /el mes pasado/i,
      Dates::Service::WEEKDAY_REGEX
    ].freeze

    def fragment_expressions
      DATE_EXPRESSION_REGEXPS.select { |word| expense.original_text.to_s.match?(word) }
    end
  end
end
