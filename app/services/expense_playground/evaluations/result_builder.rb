# frozen_string_literal: true

module ExpensePlayground
  module Evaluations
    # Converts the FINAL output of the existing Expense Playground pipeline
    # (an ExpenseCandidate) into the canonical FINAL RESULT document that is
    # compared against the dataset's expected_json.
    #
    # Every required field is always emitted so the evaluation is strict:
    # when a field the dataset expects is absent from the real result, the
    # field comparison fails.
    #
    #   ResultBuilder.call(candidate: candidate)
    #   # => { valid: true, json: { "intent" => "expense", "amount" => 20000, ... } }
    class ResultBuilder
      def self.call(candidate:)
        return { valid: false, json: nil } if candidate.nil?

        category, subcategory = category_bucket(candidate)
        {
          valid: true,
          json: {
            "intent" => "expense",
            "amount" => amount(candidate.amount),
            "date" => candidate.date&.iso8601,
            "activity" => candidate.description.presence || candidate.merchant,
            "category" => category,
            "subcategory" => subcategory,
            "money_source" => candidate.money_source_name.presence,
            "currency" => candidate.currency.presence
          }
        }
      end

      # Splits the mapped category into the top-level bucket and the specific
      # child ("subcategory") when the user's category tree is two levels deep.
      def self.category_bucket(candidate)
        record = Category.find_by(id: candidate.category_id) if candidate.category_id.present?
        return [ candidate.category_name, nil ] if record.nil? || record.parent_id.nil?

        [ record.parent&.name || candidate.category_name, record.name ]
      end

      def self.amount(value)
        return value if value.is_a?(Integer) || value.is_a?(Float)

        value.to_f if value.is_a?(Numeric)
      end
    end
  end
end
