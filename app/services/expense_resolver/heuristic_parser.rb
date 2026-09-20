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

      matches.each_with_index.filter_map do |match, index|
        previous_end = index.zero? ? 0 : matches[index - 1][:end]
        prefix = normalized[previous_end...match[:start]].to_s
        window_end = index == matches.length - 1 ? normalized.length : matches[index + 1][:start]
        window = normalized[match[:end]...window_end].to_s
        original_text = normalized[previous_end...window_end].to_s

        build_entry(raw_amount: match[:raw], prefix: prefix, window: window, original_text: original_text)
      end
    end

    private

    def build_entry(raw_amount:, prefix:, window:, original_text:)
      value, amount_confidence = Amounts::Service.interpret_amount(raw_amount)
      # The date expression normally precedes its amount ("ayer gasté…"), so
      # the prefix is checked before the following segment.
      date, date_confidence = detect_date(prefix) || detect_date(window) || [ @today, 0.95 ]
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
        confidence: confidence
      )
    end

    # Returns [Date, confidence] when an explicit date expression is found.
    def detect_date(text)
      Dates::Service.detect_date(text, today: @today)
    end
  end
end
