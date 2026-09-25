# frozen_string_literal: true

module Ai
  module Tasks
    class ParsedExpense
      LOW_CONFIDENCE_THRESHOLD = 0.75

      # Shared entry shape for every extraction origin (conversation parsing,
      # heuristic pass, vision/image extraction). Core fields come from the AI
      # task payloads; merchant/currency/money_source_* are populated by
      # channel processors (e.g. the image pipeline) before normalization.
      # signal_confidences ({amount:, date:, category:}) is only set by the
      # heuristic pass so the resolver can tell which signal is weak; every
      # other origin leaves it nil.
      ATTRIBUTES = %i[
        original_text
        amount
        date
        description
        category
        category_suggestion
        money_source_hint
        confidence
        signal_confidences
        merchant
        currency
        money_source_id
        money_source_name
      ].freeze

      attr_reader(*ATTRIBUTES)
      # Writers for the pipeline stages that refine a heuristic entry after
      # parsing (category fill in the resolver; suggestion re-broadcasting).
      attr_writer :category, :category_suggestion, :confidence, :signal_confidences

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
