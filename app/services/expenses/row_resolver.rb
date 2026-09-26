# frozen_string_literal: true

module Expenses
  # Deterministic resolver layer for tabular statement rows (CSV/XLSX).
  #
  # Structured rows keep their column values; free-text rows (the description
  # carries its own amount and/or date) are re-derived through the
  # ExpenseResolver heuristic parser, inheriting the colloquial multiplier,
  # quantity totals, date translation and correction handling. Conflicts
  # (description amount vs column amount, quantity groups, bare-bank
  # ambiguity) are flagged for review — the bank column is authoritative and
  # nothing is silently rewritten.
  class RowResolver
    Result = Struct.new(:description, :amount, :date, :warnings, :revised, keyword_init: true)

    # Bank statements echo long reference codes into every description; they
    # are noise for the user and for classification. Only long runs of
    # consecutive digits qualify (bank amounts like "180.000" keep their
    # separators), and merchant names stay intact.
    REFERENCE_CODE_REGEX = /\b\d{7,}\b/

    # Payment prefixes banks prepend to transfers ("PAGO A TRSF MERCADO").
    NOISE_TOKEN_REGEX = /\A\s*(?:pago\s+(?:a|por|de|nomina)\s*|trsf\s+|trs\s+|trd\s+|ref\s+)/i

    # Sub-centavo values do not exist in COP: smaller scanned numbers are
    # row noise ("TIENDA D1"), not amounts.
    MIN_ROW_AMOUNT = 100

    def self.call(user:, description:, amount: nil, date: nil, categories:, money_source_detector:)
      new(
        user: user,
        description: description,
        amount: amount,
        date: date,
        categories: categories,
        money_source_detector: money_source_detector
      ).call
    end

    def initialize(user:, description:, amount:, date:, categories:, money_source_detector:)
      @user = user
      @raw_description = description.to_s
      @column_amount = amount
      @column_date = date
      @categories = categories
      @detector = money_source_detector
    end

    def call
      warnings = []
      description, text_amount, text_date, revised = free_text_reading(warnings)

      if description.blank?
        description = structured_description
      else
        revised = true
      end

      warnings.concat(quantity_warnings)
      warnings.concat(source_warnings(description))

      Result.new(
        description: description.presence || @raw_description.strip,
        amount: text_amount || @column_amount,
        date: text_date || @column_date,
        warnings: warnings.uniq,
        revised: revised
      )
    end

    private

    # The row is free text when its description carries a real amount (one
    # that is not just the column value echoed) or a date expression.
    def free_text_reading(warnings)
      scan = scanned_amounts
      date_scan = date_scans
      echoed = scan.one? && @column_amount && scan.first == @column_amount

      if scan.empty?
        date = date_scan.one? ? date_scan.first : nil
        return [ noise_stripped_description, nil, date, false ] if date
        return [ nil, nil, nil, false ]
      end

      if @column_amount.nil?
        return heuristic_reading(warnings)
      end

      if echoed
        return [ echo_stripped_description, nil, nil, false ]
      end

      warnings << format_conflict_warning(scan.last, @column_amount)
      [ echo_stripped_description, nil, nil, false ]
    end

    def heuristic_reading(warnings)
      entries = ExpenseResolver::HeuristicParser.call(
        text: cleaned_text, categories: @categories, today: Date.current
      )
      entry = entries.last
      return [ nil, nil, nil, false ] if entry.blank?

      [ entry.description.to_s.strip, entry.amount&.round, entry.date, true ]
    end

    def structured_description
      strip_noise(cleaned_text)
    end

    def strip_noise(text)
      text = text.strip
      text = text.gsub(NOISE_TOKEN_REGEX, "").strip while text.match?(NOISE_TOKEN_REGEX)
      text.split(/\s+/).reject(&:blank?).join(" ")
    end

    # Descriptions that carry their own numbers keep the rest: echoed amounts
    # and filler/date/verb words are dropped, merchant text and case stay.
    def echo_stripped_description
      tokens = cleaned_text.split(/\s+/).reject do |token|
        token.match?(/\A\$?\d+(?:['.,]\s?\d{3})*\z/) ||
          filler_words.include?(normalized_token(token))
      end
      tokens.join(" ")
    end
    alias noise_stripped_description echo_stripped_description

    def filler_words
      @filler_words ||= begin
        words = %w[en de del al la las los un una unos unas que con para por y o a]
        words + ExpenseResolver::Text::Service::ACTION_WORDS.to_a +
                ExpenseResolver::Text::Service::DATE_WORDS.to_a
      end.to_set
    end

    def normalized_token(token)
      ActiveSupport::Inflector.transliterate(token.to_s).downcase
    end

    # Quantity totals the column ignores ("tres cafés de 8.500" against a
    # column of 8.500) are a flagged review case, never a rewrite.
    def quantity_warnings
      validation = ExpenseResolver::Amounts::SumValidator.call(amount: @column_amount, text: cleaned_text)
      return [] unless validation.mismatch?

      [ "Amount $#{validation.model_amount.to_i} doesn't match the itemized amounts in the text (expected $#{validation.expected_total.to_i}) — review it." ]
    end

    def source_warnings(description)
      matches = @detector ? @detector.scored_matches(description) : []
      return [] if matches.size < 2
      return [] if matches.any? { |_, score| score >= MoneySources::Detector::IDENTIFIER_POINTS }

      [ "Money source is ambiguous: the row names a bank covered by several registered sources — review it." ]
    end

    def format_conflict_warning(text_value, column_value)
      "The row text names $#{text_value.to_i} but the column value is $#{column_value.to_i} — review it."
    end

    def scanned_amounts
      ExpenseResolver::Amounts::Service.scan_amounts(cleaned_text).filter_map do |scan|
        value = amount_of(scan)
        value && value >= MIN_ROW_AMOUNT ? value : nil
      end
    end

    def date_scans
      ExpenseResolver::Dates::Service.scan_dates(cleaned_text)
    end

    def amount_of(scan)
      value, = ExpenseResolver::Amounts::Service.interpret_amount(scan[:raw], colloquial: true)
      value
    end

    def cleaned_text
      @cleaned_text ||= @raw_description.gsub(REFERENCE_CODE_REGEX, " ").squeeze(" ").strip
    end
  end
end
