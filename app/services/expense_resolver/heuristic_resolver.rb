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
      return Resolution.new(nil) unless ConfidenceGate.confident?(parsed)

      @recording&.add_step(:extraction, parsed)
      record_deterministic_resolution(parsed)
      Resolution.new(parsed)
    end

    private

    def record_deterministic_resolution(entries)
      return unless Ai.configuration.configured?

      Ai::Recorder.write(task: "expense_extraction", user: @user, strategy: "deterministic",
                         provider: nil, status: "ok", escalated: false, error: nil,
                         confidence: entries.map(&:confidence).compact.min,
                         input_tokens: nil, output_tokens: nil, latency_ms: nil)
    end
  end
end
