# frozen_string_literal: true

module ExpenseResolver
  # Presents resolved ExpenseCandidates as plain hashes for the parse endpoint.
  # Keys mirror the shape the AI entry form (app/views/expenses/_ai_entry.html.erb)
  # consumes: amount, description, transaction_date, category_id, category_name,
  # confidence, low_confidence, warnings and money source fields.
  class Serializer
    def self.call(candidates)
      candidates.map { |candidate| serialize(candidate) }
    end

    private

    def self.serialize(candidate)
      {
        amount: candidate.amount&.to_f,
        description: candidate.description,
        transaction_date: candidate.date&.iso8601,
        category_id: candidate.category_id,
        category_name: candidate.category_name || candidate.suggested_category_name,
        create_category: candidate.suggested_category_name.present?,
        confidence: candidate.confidence,
        low_confidence: candidate.confidence.to_f < Ai::Tasks::ParsedExpense::LOW_CONFIDENCE_THRESHOLD,
        warnings: warnings(candidate),
        money_source_id: candidate.money_source_id,
        money_source_name: candidate.money_source_name
      }
    end

    def self.warnings(candidate)
      candidate.warnings.to_a
    end
  end
end
