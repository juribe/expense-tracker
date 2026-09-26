# frozen_string_literal: true

module ExpenseResolver
  # Deterministic first pass over natural-language text, tried before any AI
  # call. Entries are returned only when every field resolved confidently
  # (ExpenseResolver::ConfidenceGate); otherwise the AI has to take care of
  # the text.
  #
  #   ExpenseResolver::HeuristicResolver.call(text:, user:, categories:, recording:)
  #   => Resolution(entries: [Ai::Tasks::ParsedExpense, ...])  # resolved?
  class HeuristicResolver
    Resolution = Struct.new(:entries) do
      def resolved?
        entries.present?
      end
    end

    def self.call(text:, user:, categories:, recording: nil)
      new(text: text, user: user, categories: categories, recording: recording).call
    end

    def initialize(text:, user:, categories:, recording: nil)
      @text = text
      @user = user
      @categories = categories
      @recording = recording
    end

    def call
      parsed = ExpenseResolver::HeuristicParser.call(text: @text, categories: @categories)

      # When only the category is weak, a small category call is the
      # right-sized escalation: cheaper than the full parse and it keeps the
      # deterministic amount/date readings authoritative. AI_DISABLE_CATEGORY_FILL
      # skips it; the full parse's own category second pass covers the gap.
      unless Ai.configuration.category_fill_disabled?
        resolved = resolve_weak_categories(parsed)
        parsed = resolved if resolved
      end

      return Resolution.new(nil) unless ConfidenceGate.confident?(parsed)

      @recording&.add_step(:extraction, parsed)
      record_deterministic_resolution(parsed)
      Resolution.new(parsed)
    end

    private

    # Fills categories for entries whose amount and date resolved confidently
    # but whose category is below the deterministic threshold. Stored user
    # knowledge resolves repeats for free; the rest is batched through one
    # small category-suggestion call. Returns the updated entries, or nil to
    # escalate the whole text to the full AI parse (another signal is weak,
    # the call failed, or the suggestion is not confident enough).
    def resolve_weak_categories(entries)
      pending = entries.select { |entry| weak_category?(entry) }

      if pending.any?
        return nil unless all_core_signals_confident?(entries)

        fill_categories(entries, pending) || return
      end

      entries
    end

    def weak_category?(entry)
      signals = entry.signal_confidences
      return false if signals.blank?

      signals[:category].to_f < Ai.configuration.deterministic_threshold
    end

    def all_core_signals_confident?(entries)
      threshold = Ai.configuration.deterministic_threshold
      entries.all? do |entry|
        signals = entry.signal_confidences
        next true if signals.blank?

        signals[:amount].to_f >= threshold && signals[:date].to_f >= threshold
      end
    end

    # Returns true when the fill left every entry at or above the threshold.
    def fill_categories(entries, pending)
      fill_from_stored_knowledge(entries, pending)
      fill_from_suggestion(entries, pending) if pending.any?

      ConfidenceGate.confident?(entries)
    end

    def fill_from_stored_knowledge(entries, pending)
      pending.each do |entry|
        stored = ActivityClassification.lookup(user: @user, name: entry.description.to_s)
        next unless stored&.category

        # Stored knowledge is a real user category: set it directly, no
        # confirmation flow needed.
        entry.category = stored.category.name
        update_entry_confidence(entry, 1.0)
      end
    end

    def fill_from_suggestion(entries, pending)
      items = pending.each_with_index.map do |(entry, _), position|
        { "index" => position, "description" => entry.description.to_s }
      end

      result = Ai::Router.call(task: :category_suggestion, input: items, context: { user: @user })
      return unless result.ok?

      pending.each_with_index do |(entry, _), position|
        suggestion = result.data[position.to_s] || result.data[position]
        next if suggestion.blank?

        entry.category_suggestion = suggestion
        update_entry_confidence(entry, result.confidence.to_f)
      end
    end

    # The suggestion's confidence becomes the category signal in the re-gate;
    # below the threshold it stays a user-confirmation suggestion.
    def update_entry_confidence(entry, category_confidence)
      signals = entry.signal_confidences
      return if signals.blank?

      entry.signal_confidences = { amount: signals[:amount], date: signals[:date], category: category_confidence }
      entry.confidence = [ signals[:amount].to_f, signals[:date].to_f, category_confidence ].min.round(2)
    end

    def record_deterministic_resolution(entries)
      return unless Ai.configuration.configured?

      Ai::Recorder.write(task: "expense_extraction", user: @user, strategy: "deterministic",
                         provider: nil, status: "ok", escalated: false, error: nil,
                         confidence: entries.map(&:confidence).compact.min,
                         input_tokens: nil, output_tokens: nil, latency_ms: nil)
    end
  end
end
