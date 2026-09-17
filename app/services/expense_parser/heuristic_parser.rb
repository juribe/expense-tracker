class ExpenseParser
  class HeuristicParser
    def initialize(text:, today:, categories:)
      @text = text.to_s.strip
      @today = today
      @categories = categories
    end

    def parse
      normalized = ExpenseParser::TextService.normalize_text(@text)
      matches = ExpenseParser::AmountService.scan_amounts(normalized)
      return [] if matches.empty?

      matches.each_with_index.filter_map do |match, index|
        previous_end = index.zero? ? 0 : matches[index - 1][:end]
        prefix = normalized[previous_end...match[:start]].to_s
        window_end = index == matches.length - 1 ? normalized.length : matches[index + 1][:start]
        window = normalized[match[:end]...window_end].to_s

        build_entry(raw_amount: match[:raw], prefix: prefix, window: window)
      end
    end

    private

    def build_entry(raw_amount:, prefix:, window:)
      value, amount_confidence = ExpenseParser::AmountService.interpret_amount(raw_amount)
      # The date expression normally precedes its amount ("ayer gasté…"), so
      # the prefix is checked before the following segment.
      date, date_confidence = detect_date(prefix) || detect_date(window) || [ @today, 0.95 ]
      description = ExpenseParser::TextService.clean_description(window).presence || ExpenseParser::TextService.clean_description(prefix).presence

      resolution = ExpenseParser::CategoryService.resolve_category(description, window, @categories)

      warnings = []
      warnings << "We are not sure about this expense amount. Detected: $#{value.to_i}" if amount_confidence < ParsedExpense::LOW_CONFIDENCE_THRESHOLD
      warnings << "We assumed the date is #{date.iso8601}. Please confirm." if date_confidence < ParsedExpense::LOW_CONFIDENCE_THRESHOLD
      if resolution.category.nil? && resolution.suggested_name.present?
        warnings << "No matching category found. A new \"#{resolution.suggested_name}\" category will be created."
      elsif resolution.category.nil?
        warnings << "We could not determine a category for this expense. You can assign it when you confirm."
      end

      confidence = [ amount_confidence, date_confidence, resolution.confidence ].min.round(2)

      ParsedExpense.new(
        amount: BigDecimal(value.to_s),
        description: description.presence || resolution.suggested_name,
        transaction_date: date,
        category_id: resolution.category&.id,
        category_name: resolution.category&.name || resolution.suggested_name,
        create_category: resolution.category.nil? && resolution.suggested_name.present?,
        confidence: confidence,
        warnings: warnings
      )
    end

    # Returns [Date, confidence] when an explicit date expression is found.
    def detect_date(text)
      ExpenseParser::DateService.detect_date(text, today: @today)
    end
  end
end
