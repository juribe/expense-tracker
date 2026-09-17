class ExpenseParser
  class Provider
    # Deterministic amount readings confident enough to override an AI value.
    # "20 mil"/"20 lucas"/"50.000" read at >= 0.8; a bare word-number or an
    # unformatted integer stays below and never overrides.
    RECONCILE_CONFIDENCE_THRESHOLD = 0.8

    def initialize(text:, user:, today:, categories:, context: nil, execution: nil, notes:)
      @text = text.to_s.strip
      @user = user
      @today = today
      @context = context.to_s.presence
      @execution = execution
      @categories = categories
      @notes = notes
    end

    # Resolution order: deterministic heuristic → AI routing (cheap model first,
    # strong model on low confidence or failure) → heuristic fallback. When the
    # heuristic pass resolves every expense confidently, no AI call happens.
    def run
      heuristic_parser = ExpenseParser::HeuristicParser.new(text: @text, today: @today, categories: @categories)
      heuristic = heuristic_parser.parse

      if force_ai?
        entries, strategy = parse_with_routing
        return [ entries, "ai", strategy ] if entries.present?

        return [ heuristic, "heuristic", nil ]
      end

      if deterministic_confident?(heuristic)
        record_deterministic_resolution(heuristic)
        return [ heuristic, "heuristic", "deterministic" ]
      end

      entries, strategy = parse_with_routing
      return [ entries, "ai", strategy ] if entries.present?

      [ heuristic, "heuristic", nil ]
    end

    private

    def parse_with_routing
      return nil, nil unless ai_configured?

      result = Ai::Router.call(
        task: :expense_extraction,
        input: @text,
        context: { user: @user, today: @today, categories: @categories, context: @context, execution: @execution }
      )
      unless result.ok?
        @notes << "AI parsing failed, used rule-based fallback (#{result.error})."
        return nil, nil
      end

      entries = result.data.map { |entry| normalize_ai_entry(entry) }
      entries = reconcile_amounts(entries)
      entries.present? ? [ entries, result.strategy ] : [ nil, nil ]
    end

    # Maps a raw AI hash (from the router) into the internal entry shape used
    # by build_expense:
    #   { amount:, description:, transaction_date:, category_name:, create_category:, confidence: }
    def normalize_ai_entry(entry)
      entry = entry.with_indifferent_access
      {
        amount: entry[:amount],
        description: entry[:description].presence,
        transaction_date: ExpenseParser::DateService.parse_iso_date(entry[:transaction_date]) || @today,
        category_name: entry[:category_name].presence || entry[:category].presence,
        create_category: entry[:create_category],
        confidence: entry[:confidence],
        source_hint: nil
      }
    end

    # The AI occasionally misexpands Colombian amounts ("20 mil" read as
    # 2.000.000). When the message carries exactly one unambiguous amount
    # expression, prefer the deterministic reading (which is how the heuristic
    # parser reports the same text) over the AI value.
    def reconcile_amounts(entries)
      return entries if entries.length != 1

      recovered, confidence = deterministic_amount
      return entries if recovered.nil? || confidence < RECONCILE_CONFIDENCE_THRESHOLD

      entry = entries.first
      entry[:amount] = recovered
      entry[:confidence] = [ entry[:confidence].to_f, confidence ].min
      [ entry ]
    end

    # Deterministic amount recovered from the source text: nil unless exactly
    # one amount expression is present and confidently interpretable.
    def deterministic_amount
      matches = ExpenseParser::AmountService.scan_amounts(ExpenseParser::TextService.normalize_text(@text))
      uniques = matches.map { |match| match[:raw] }.uniq
      return [ nil, 0.0 ] unless uniques.length == 1

      ExpenseParser::AmountService.interpret_amount(uniques.first)
    end

    # Heuristic entries with every confidence component at or above the
    # deterministic threshold are trusted without an AI call.
    def deterministic_confident?(entries)
      return false if entries.empty?

      threshold = Ai.configuration.deterministic_threshold
      entries.all? { |expense| expense.confidence.to_f >= threshold && expense.warnings.blank? }
    end

    def record_deterministic_resolution(entries)
      # Only worth recording when an AI call would otherwise have happened.
      return unless ai_configured?

      Ai::Recorder.write(task: "expense_extraction", user: @user, strategy: "deterministic",
                         provider: nil, status: "ok", escalated: false, error: nil,
                         confidence: entries.map(&:confidence).compact.min,
                         input_tokens: nil, output_tokens: nil, latency_ms: nil)
    end

    def ai_configured?
      return configured_override? if @execution&.override?

      ENV["MISTRAL_API_KEY"].present? || Ai.configuration.cheap_enabled?
    end

    def force_ai?
      @execution&.force_ai? || false
    end

    # An evaluation override is usable when the requested vendor client builds
    # and carries a key/endpoint; e.g. OpenRouter reads OPENROUTER_API_KEY.
    def configured_override?
      provider = Ai::Providers.build(provider: @execution.provider, model: @execution.model)
      provider&.configured?
    rescue ArgumentError
      false
    end
  end
end
