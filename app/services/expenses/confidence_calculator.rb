# frozen_string_literal: true

module Expenses
  # Deterministic confidence scoring for an AI-parsed expense. The score is a
  # weighted sum of verifiable signals (weights add up to 1.0), so a missing
  # signal simply does not earn its weight and inconsistent data takes a fixed
  # penalty. Every awarded/lost point is recorded in `reasons` so a score is
  # always explainable. The AI model itself is never asked for a confidence.
  #
  #   result = Expenses::ConfidenceCalculator.call(
  #     expense: parsed_expense,   # responds to original_text/amount/date/description/category
  #     input: original_input,     # the raw user text the expense was parsed from
  #     categories: [Category],    # categories available to the user (records or names)
  #     today: Date.current
  #   )
  #   result.score    # => 0.0..1.0 (BigDecimal-friendly Float)
  #   result.reasons  # => ["amount 50000 explicitly found in original text (+0.15)", ...]
  class ConfidenceCalculator
    Result = Struct.new(:score, :reasons, keyword_init: true) do
      def to_h
        { score: score, reasons: reasons }
      end
    end

    WEIGHTS = {
      original_text: 0.10,
      amount: 0.30,
      amount_in_text: 0.15,
      date: 0.10,
      date_in_text: 0.10,
      description: 0.15,
      category: 0.10
    }.freeze

    FUTURE_DATE_PENALTY = 0.10

    def self.call(expense:, input:, categories: [], today: Date.current)
      new(expense: expense, input: input, categories: categories, today: today).call
    end

    def initialize(expense:, input:, categories: [], today: Date.current)
      @expense = expense
      @input = input.to_s
      @category_names = Array(categories).map do |category|
        category.respond_to?(:name) ? category.name : category.to_s
      end
      @today = today
    end

    def call
      points = 0.0
      reasons = []

      points += original_text_signal(reasons)
      points += amount_signal(reasons)
      points += amount_in_text_signal(reasons)
      points += date_signal(reasons)
      points += date_in_text_signal(reasons)
      points += description_signal(reasons)
      points += category_signal(reasons)
      points -= future_date_penalty(reasons)

      Result.new(score: points.round(2).clamp(0.0, 1.0), reasons: reasons)
    end

    private

    def original_text_signal(reasons)
      text = @expense.original_text.to_s.strip
      if text.blank?
        reasons << "original_text missing (+0.00 of #{WEIGHTS[:original_text]})"
        return 0.0
      end

      if normalize(@input).include?(normalize(text))
        reasons << "original text matches a portion of the input (+#{WEIGHTS[:original_text]})"
        WEIGHTS[:original_text]
      else
        reasons << "original text does not match the input (half credit, possible hallucination)"
        WEIGHTS[:original_text] / 2
      end
    end

    def amount_signal(reasons)
      if valid_amount?
        reasons << "amount #{format_amount} present and valid (+#{WEIGHTS[:amount]})"
        WEIGHTS[:amount]
      else
        reasons << "amount missing or invalid (+0.00 of #{WEIGHTS[:amount]})"
        0.0
      end
    end

    def amount_in_text_signal(reasons)
      if amount_in_text?
        reasons << "amount #{format_amount} explicitly found in original text (+#{WEIGHTS[:amount_in_text]})"
        WEIGHTS[:amount_in_text]
      else
        reasons << "amount not found in the original text (inferred) (+0.00 of #{WEIGHTS[:amount_in_text]})"
        0.0
      end
    end

    def date_signal(reasons)
      if expense_date
        reasons << "date #{expense_date.iso8601} present and valid (+#{WEIGHTS[:date]})"
        WEIGHTS[:date]
      else
        reasons << "date missing or invalid (+0.00 of #{WEIGHTS[:date]})"
        0.0
      end
    end

    def date_in_text_signal(reasons)
      return 0.0 unless expense_date

      resolved = verifiable_texts.any? do |text|
        detected, = ExpenseResolver::Dates::Service.detect_date(text, today: @today)
        detected == expense_date
      end
      if resolved
        reasons << "date resolved from the original text (explicit or relative) (+#{WEIGHTS[:date_in_text]})"
        WEIGHTS[:date_in_text]
      else
        reasons << "date not derivable from the original text (inferred) (+0.00 of #{WEIGHTS[:date_in_text]})"
        0.0
      end
    end

    def description_signal(reasons)
      description = @expense.description.to_s.strip
      if description.length >= 3 && description !~ /\A[\d\s.,]+\z/
        reasons << "description \"#{description}\" is present and meaningful (+#{WEIGHTS[:description]})"
        WEIGHTS[:description]
      else
        reasons << "description missing, too short or not meaningful (+0.00 of #{WEIGHTS[:description]})"
        0.0
      end
    end

    def category_signal(reasons)
      name = @expense.category.to_s.strip
      if name.blank?
        reasons << "category missing (+0.00 of #{WEIGHTS[:category]})"
        return 0.0
      end

      if normalize(@category_names.find { |candidate| normalize(candidate) == normalize(name) }).present?
        reasons << "category \"#{name}\" is one of the available categories (+#{WEIGHTS[:category]})"
        WEIGHTS[:category]
      else
        reasons << "category \"#{name}\" is not among the available categories (+0.00 of #{WEIGHTS[:category]})"
        0.0
      end
    end

    # Inconsistent dates are the one hard penalty: a future date on an expense
    # is never legitimate.
    def future_date_penalty(reasons)
      return 0.0 unless expense_date && expense_date > @today

      reasons << "date is in the future (penalty -#{FUTURE_DATE_PENALTY})"
      FUTURE_DATE_PENALTY
    end

    def valid_amount?
      @expense.amount.is_a?(Numeric) && @expense.amount.positive?
    end

    def format_amount
      @expense.amount.to_s
    end

    # The amount must be derivable from the text the expense came from
    # ("50 mil" == 50000); anything else was inferred, not extracted. The
    # claimed original_text is scanned first, then the full user input, since
    # relative hints may fall just outside the claimed slice.
    def amount_in_text?
      return false unless valid_amount?

      target = @expense.amount.to_d
      verifiable_texts.any? do |text|
        next false if text.strip.blank?

        ExpenseResolver::Amounts::Service.scan_amounts(text).any? do |scan|
          value, = ExpenseResolver::Amounts::Service.interpret_amount(scan[:raw], colloquial: true)
          value && (value.to_d - target).abs <= BigDecimal("0.01")
        end
      end
    end

    def verifiable_texts
      [ @expense.original_text.to_s, @input ]
    end

    def expense_date
      @expense_date ||= ExpenseResolver::Dates::Service.parse_iso_date(@expense.date)
    end

    def normalize(text)
      ActivityClassification.normalize_name(text).to_s
    end
  end
end
