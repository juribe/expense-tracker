# frozen_string_literal: true

module ExpenseResolver
  # Decides whether a heuristic parsing pass is deterministic-confident enough
  # to skip the AI call entirely: the pass must have produced at least one
  # entry and every entry must sit at or above the deterministic threshold
  # with no warnings that would require user confirmation.
  module ConfidenceGate
    module_function

    def confident?(entries)
      return false if entries.empty?

      threshold = Ai.configuration.deterministic_threshold
      entries.all? do |entry|
        entry.confidence.to_f >= threshold && Array(entry.try(:warnings)).blank?
      end
    end
  end
end
