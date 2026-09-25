# frozen_string_literal: true

module ExpenseResolver
  class CandidateDetector
    attr_accessor :expense, :user, :categories, :money_source_detector, :classification_source, :text, :recording, :allow_text_heuristics

    def self.call(expense:, user:, categories: nil, money_source_detector: nil, classification_source: "ai", text: nil, recording: nil, allow_text_heuristics: true)
      new(expense: expense, user: user, categories: categories, money_source_detector: money_source_detector, classification_source: classification_source, text: text, recording: recording, allow_text_heuristics: allow_text_heuristics).call
    end

    def initialize(expense:, user:, categories: nil, money_source_detector: nil, classification_source: "ai", text: nil, recording: nil, allow_text_heuristics: true)
      self.expense = expense
      self.user = user
      self.categories = categories
      self.money_source_detector = money_source_detector
      self.classification_source = classification_source
      self.text = text
      self.recording = recording
      self.allow_text_heuristics = allow_text_heuristics
    end

    def call
      suggested = category_result.suggested_category_name.presence ||
                  (expense.respond_to?(:category_suggestion) ? expense.category_suggestion : nil)

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
        warnings: category_result.warnings + money_source_warnings
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
        allow_heuristic: allow_text_heuristics
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
