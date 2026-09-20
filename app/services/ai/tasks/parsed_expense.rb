# frozen_string_literal: true

module Ai
  module Tasks
    class ParsedExpense
      LOW_CONFIDENCE_THRESHOLD = 0.75

      # Shared entry shape for every extraction origin (conversation parsing,
      # heuristic pass, vision/image extraction). Core fields come from the AI
      # task payloads; merchant/currency/money_source_* are populated by
      # channel processors (e.g. the image pipeline) before normalization.
      ATTRIBUTES = %i[
        original_text
        amount
        date
        description
        category
        money_source_hint
        confidence
        merchant
        currency
        money_source_id
        money_source_name
      ].freeze

      attr_reader(*ATTRIBUTES)

      def initialize(**attributes)
        attributes.each do |key, value|
          instance_variable_set("@#{key}", value)
        end
      end

      def self.build_expense(entry)
        entry = entry.transform_keys(&:to_s)

        attributes = ATTRIBUTES.to_h do |attribute|
          value = entry[attribute.to_s]
          value = value.strip if value.is_a?(String)

          [ attribute.to_sym, value ]
        end

        new(**attributes)
      end
    end
  end
end
