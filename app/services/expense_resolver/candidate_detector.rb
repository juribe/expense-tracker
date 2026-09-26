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
        warnings: category_result.warnings + money_source_warnings + amount_sum_warnings + refund_warnings
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
    # entry's own text is flagged for review — never rewritten. When the
    # fragment dropped the itemization entirely, the single-entry fallback
    # reads the full message: a quantity the model lost ("tres cafés de
    # 8.500") must not pass silently.
    def amount_sum_warnings
      validation = Amounts::SumValidator.call(amount: expense.amount, text: expense.original_text)
      if !validation.itemized && text.present? && (entry_count.nil? || entry_count == 1)
        validation = Amounts::SumValidator.call(amount: expense.amount, text: text)
      end
      return [] unless validation.mismatch?

      model_amount = format_money(validation.model_amount)
      expected = format_money(validation.expected_total)
      [ "Amount #{model_amount} doesn't match the itemized amounts in the text (expected #{expected}) — review it." ]
    end

    def format_money(value)
      formatted = value.to_i == value ? value.to_i : value.to_f
      "$#{formatted.to_s.gsub(/\.0\z/, "")}"
    end

    # Refunds and adjustments ("me devolvieron 30.000", "tenía un descuento")
    # must never be netted silently into the purchase amount: the expense
    # stays at the full price and the mention goes to the user for review.
    REFUND_PHRASE_REGEX = /\b(?:me\s+)?(?:devolv\p{L}*|devoluci\p{L}*|recarg\p{L}*|descuento|rebaja)\b/i
    REFUND_AMOUNT_REGEX = /\b(?:me\s+)?(?:devolv\p{L}*|recarg\p{L}*|descuento\p{L}*|rebaja\p{L}*)\b[^0-9]{0,24}\$?\s*(\d[\d.,]*)/i

    def refund_warnings
      slice = ExpenseResolver::Text::Service.cut_payment_clause(
        ExpenseResolver::MoneySourceResult.slice_for(expense)
      )

      warning = refund_warning_for(slice)
      return [ warning ] if warning

      # The model sometimes drops the refund clause from the entry fragment:
      # the deterministic reading of the full message keeps the guard from
      # going blind. The mention may belong to another entry, so the wording
      # stays the same non-negotiable review flag.
      return [] if text.blank?

      full_warning = refund_warning_for(text)
      full_warning ? [ full_warning ] : []
    end

    def refund_warning_for(slice)
      match = REFUND_AMOUNT_REGEX.match(slice)
      if match
        value, = ExpenseResolver::Amounts::Service.interpret_amount(match[1], colloquial: false)
        if value && value != expense.amount
          return "Text mentions a refund or adjustment of #{format_money(value)} — confirm the amount is the full purchase price before confirming."
        end
      end

      "Text mentions a refund or adjustment — confirm the amount is the full purchase price before confirming." if slice.match?(REFUND_PHRASE_REGEX)
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
      warnings = []
      if money_source_result.review
        name = money_source_result.money_source_name.presence || "the detected source"
        warnings << "Money source \"#{name}\" suggested from a tight match — review it before confirming."
      end

      warnings + unsplit_transaction_warnings
    end

    # When the entry's own fragment names several distinct registered money
    # sources, the model likely merged transactions that were paid differently
    # (e.g. "zapatos con la tarjeta y camisa con la cuenta" in one expense).
    # The source stays resolved; the split decision goes to the user.
    def unsplit_transaction_warnings
      detector = money_source_detector
      slice = ExpenseResolver::Text::Service.cut_payment_clause(
        ExpenseResolver::MoneySourceResult.slice_for(expense)
      )

      # Bank-level matches are shared by every product of the same bank and
      # never signal a split; only explicit identifier mentions do.
      identifier_sources = detector.scored_matches(slice)
                                   .select { |_, score| score >= MoneySources::Detector::IDENTIFIER_POINTS }
                                   .map(&:first).map(&:id).uniq
      return [] unless identifier_sources.size > 1

      [ "This entry may contain several transactions paid with different money sources — review the split." ]
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
