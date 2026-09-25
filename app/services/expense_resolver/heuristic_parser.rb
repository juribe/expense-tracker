# frozen_string_literal: true

module ExpenseResolver
  # Deterministic first pass over natural-language text, callable before the
  # AI path. It scans amount expressions, resolves dates, descriptions and
  # categories with the themed field services (Amounts, Dates, Text,
  # Categories) and maps each result into the Ai::Tasks::ParsedExpense shape
  # the resolver pipeline already consumes, so heuristic entries flow through
  # CandidateDetector exactly like AI entries.
  #
  #   ExpenseResolver::HeuristicParser.call(text:, categories:, today:)
  #   => [Ai::Tasks::ParsedExpense, ...]
  class HeuristicParser
    # A new date expression inside an amount's window opens the NEXT expense's
    # segment ("...en parqueadero, hoy compré 10 mil en pan"), so the window
    # must stop there for date and description purposes.
    DATE_BOUNDARY_REGEX = /\b(?:hoy|ayer|anteayer|lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b/
    SPENDING_VERB_REGEX = /\b(?:gast|compr|pag|cobr)\w*/

    def self.call(text:, categories:, today: Date.current)
      new(text: text, categories: categories, today: today).call
    end

    def initialize(text:, categories:, today:)
      @text = text.to_s.strip
      @today = today
      @categories = categories
    end

    def call
      normalized = Text::Service.normalize_text(@text)
      matches = Amounts::Service.scan_amounts(normalized)
      return [] if matches.empty?

      # A date expression scopes every expense that follows it until a new
      # one appears ("Ayer gasté 45.000 en almuerzo, 18.000 en un taxi").
      carried_date = nil

      matches.each_with_index.filter_map do |match, index|
        previous_end = index.zero? ? 0 : matches[index - 1][:end]
        prefix = normalized[previous_end...match[:start]].to_s
        window_end = index == matches.length - 1 ? normalized.length : matches[index + 1][:start]
        segment = normalized[match[:end]...window_end].to_s
        window = expense_window(segment)
        original_text = normalized[previous_end...window_end].to_s

        date_info = detect_date(prefix) || detect_date(window)
        carried_date = date_info if date_info
        date, date_confidence = date_info || carried_date || [ @today, 0.95 ]

        build_entry(
          raw_amount: match[:raw],
          prefix: prefix,
          window: window,
          original_text: original_text,
          date: date,
          date_confidence: date_confidence
        )
      end
    end

    private

    # Trims the segment at a date expression that opens the next expense.
    # The cut only happens when spending text follows the date word ("hoy
    # compré…"); a bare trailing date ("en almuerzo, ayer") belongs to the
    # current expense.
    def expense_window(segment)
      boundary = segment.index(DATE_BOUNDARY_REGEX)
      return segment if boundary.nil?

      segment[boundary..].match?(SPENDING_VERB_REGEX) ? segment[0...boundary] : segment
    end

    def build_entry(raw_amount:, prefix:, window:, original_text:, date:, date_confidence:)
      value, amount_confidence = Amounts::Service.interpret_amount(raw_amount, colloquial: true)
      description = Text::Service.clean_description(window).presence || Text::Service.clean_description(prefix).presence

      resolution = Categories::Service.resolve_category(description, window, @categories)

      confidence = [ amount_confidence, date_confidence, resolution.confidence ].min.round(2)

      Ai::Tasks::ParsedExpense.new(
        original_text: original_text.strip.presence || @text,
        amount: BigDecimal(value.to_s),
        date: date,
        description: description.presence || resolution.suggested_name,
        category: resolution.category&.name || resolution.suggested_name,
        money_source_hint: nil,
        confidence: confidence,
        signal_confidences: {
          amount: amount_confidence.round(2),
          date: date_confidence.round(2),
          category: resolution.confidence.round(2)
        }
      )
    end

    # Returns [Date, confidence] when an explicit date expression is found.
    def detect_date(text)
      Dates::Service.detect_date(text, today: @today)
    end
  end
end
