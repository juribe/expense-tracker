# frozen_string_literal: true

module ExpenseResolver
  class CandidateDetector
    attr_accessor :expense, :user, :categories, :money_source_detector, :classification_source, :text, :recording, :allow_text_heuristics, :entry_position, :entry_count

    def self.call(expense:, user:, categories: nil, money_source_detector: nil, classification_source: "ai", text: nil, recording: nil, allow_text_heuristics: true, entry_position: nil, entry_count: nil)
      new(expense: expense, user: user, categories: categories, money_source_detector: money_source_detector, classification_source: classification_source, text: text, recording: recording, allow_text_heuristics: allow_text_heuristics, entry_position: entry_position, entry_count: entry_count).call
    end

    def initialize(expense:, user:, categories: nil, money_source_detector: nil, classification_source: "ai", text: nil, recording: nil, allow_text_heuristics: true, entry_position: nil, entry_count: nil)
      self.expense = expense
      self.user = user
      self.categories = categories
      self.money_source_detector = money_source_detector
      self.classification_source = classification_source
      self.text = text
      self.recording = recording
      self.allow_text_heuristics = allow_text_heuristics
      self.entry_position = entry_position
      self.entry_count = entry_count
    end

    def call
      # The raw entry suggestion is only surfaced when the category is still
      # unresolved: a resolved category makes the suggestion redundant (and
      # would otherwise re-flag "create category" for an existing category).
      suggested = if category_result.category
        category_result.suggested_category_name.presence
      else
        category_result.suggested_category_name.presence ||
          (expense.respond_to?(:category_suggestion) ? expense.category_suggestion : nil)
      end

      candidate = ExpenseCandidate.new(
        amount: amount_result.amount,
        currency: expense.currency.presence || ExpenseCandidate::DEFAULT_CURRENCY,
        category_id: category_result.category&.id,
        category_name: category_result.category_name,
        description: description_result.description,
        merchant: expense.respond_to?(:merchant) ? expense.merchant : nil,
        date: date_result.date,
        source: "playground",
        classification_source: classification_source,
        suggested_category_name: suggested,
        confidence: expense.confidence,
        money_source_name: money_source_result.money_source_name,
        money_source_id: money_source_result.money_source&.id,
        warnings: category_result.warnings + money_source_warnings + amount_sum_warnings
      )
      candidate.money_source_source = "suggested" if money_source_result.review
      candidate = apply_matching_rule_category(candidate)
      record_category_warnings(candidate)
      candidate
    end

    def amount_result
      @amount_result ||= AmountResult.call(
        amount: expense.amount,
        text: expense.original_text,
        allow_heuristic: allow_text_heuristics
      )
    end

    # An AI-merged amount that disagrees with the itemized amounts in the
    # entry's own text is flagged for review — never rewritten.
    def amount_sum_warnings
      validation = Amounts::SumValidator.call(amount: expense.amount, text: expense.original_text)
      return [] unless validation.mismatch?

      model_amount = format_money(validation.model_amount)
      expected = format_money(validation.expected_total)
      [ "Amount #{model_amount} doesn't match the itemized amounts in the text (expected #{expected}) — review it." ]
    end

    def format_money(value)
      formatted = value.to_i == value ? value.to_i : value.to_f
      "$#{formatted.to_s.gsub(/\.0\z/, "")}"
    end

    def category_result
      @category_result ||= CategoryResult.call(
        expense: expense,
        user: user,
        categories: categories
      )
    end

    def description_result
      @description_result ||= DescriptionResult.call(expense: expense)
    end

    def date_result
      @date_result ||= DateResult.call(
        expense: expense,
        allow_heuristic: allow_text_heuristics,
        full_text: text,
        entry_position: entry_position,
        entry_count: entry_count
      )
    end

    def money_source_result
      @money_source_result ||= MoneySourceResult.call(
        expense: expense,
        user: user,
        money_source_detector: money_source_detector,
        text: text
      )
    end

    # A tied best score still selects a source but must be reviewed: the
    # warning surfaces it in the parse UI next to the other decision notes.
    def money_source_warnings
      return [] unless money_source_result.review

      name = money_source_result.money_source_name.presence || "the detected source"
      [ "Money source \"#{name}\" suggested from a tight match — review it before confirming." ]
    end

    # The preview must reflect what will actually be saved: when a transaction
    # rule matches the detected expense, its category replaces the resolver's
    # suggestion, so no "new category will be created" path is shown.
    def apply_matching_rule_category(candidate)
      probe = Expense.new(user: user,
                          description: candidate.description.presence,
                          amount: candidate.amount,
                          money_source_id: candidate.money_source_id)
      rule = TransactionRules::Applicator.new(user).matching_category_rule(probe)
      return candidate if rule.nil?

      candidate.category_id = rule.category_id
      candidate.category_name = rule.category.name
      candidate.suggested_category_name = nil
      candidate.category_suggestion = nil if candidate.respond_to?(:category_suggestion=)
      candidate.warnings = []
      candidate
    end

    private

    # The decision warnings live on the candidate for every consumer (e.g. the
    # parse endpoint serializer); when a recording is present the pipeline
    # debug view gets them too.
    def record_category_warnings(candidate)
      return unless recording
      return if candidate.warnings.blank?

      recording.add_warnings(candidate.warnings)
    end
  end
end
