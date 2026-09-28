# frozen_string_literal: true

module Expenses
  module FileImport
    module Enrichers
      # Confidence reflects what the row actually went through: review warnings
      # and an unlinked money source are exactly the rows the user should look
      # at first, so they rank lower than a clean row.
      class Confidence
        def call(candidates)
          candidates.each { |candidate| candidate.confidence = row_confidence(candidate) }
          candidates
        end

        private

        def row_confidence(candidate)
          confidence = candidate.confidence.to_f.zero? ? 0.9 : candidate.confidence.to_f
          confidence -= 0.1 if candidate.warnings.to_a.any?
          confidence -= 0.1 if candidate.money_source_source == "missing"
          confidence.round(2)
        end
      end
    end
  end
end
