# frozen_string_literal: true

module Ai
  module Tasks
    class ParsedExpense
      ATTRIBUTES = %i[
        original_text
        amount
        date
        description
        category
        money_source_hint
        confidence
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
