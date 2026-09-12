# frozen_string_literal: true

module ExpensePlayground
  module Evaluations
    # Field-by-field comparison between the expected FINAL result and the one
    # produced by the existing Expense Playground pipeline.
    #
    # Only the fields actually present in the expected document are compared,
    # so datasets may omit optional columns. A case is a FULL success only
    # when every present required field matches:
    #
    #   Comparator.call(expected: {...}, actual: {...})
    #   # => { valid: true, matched: true, full_match: true,
    #   #      fields: { amount: {compared: true, matched: true}, ... } }
    #
    # Required fields compared when present: intent, amount, date, activity,
    # category, subcategory, money_source, currency.
    class Comparator
      REQUIRED_FIELDS = %i[
        intent amount date activity category subcategory money_source currency
      ].freeze

      attr_reader :expected, :actual

      def self.call(expected:, actual:)
        new(expected: expected, actual: actual).call
      end

      def initialize(expected:, actual:)
        @expected = expected
        @actual = actual
      end

      def call
        return { valid: false, matched: false, full_match: false, fields: {} } unless comparable?

        fields = REQUIRED_FIELDS.each_with_object({}) do |field, hash|
          hash[field] = compare(field)
        end

        # full_match requires EVERY required field present in the expected
        # document to match.
        full_match = compared_fields(fields).all? { |_field, result| result[:matched] }

        {
          valid: true,
          matched: full_match,
          full_match: full_match,
          fields: fields
        }
      end

      private

      def comparable?
        actual.is_a?(Hash) && expected.is_a?(Hash) && expected.present?
      end

      def compared_fields(fields)
        fields.select { |_field, result| result[:compared] }
      end

      def compare(field)
        expected_value = expected[field.to_s] || expected[field]
        return { compared: false, matched: false, expected: expected_value, actual: nil } if blank?(expected_value)

        actual_value = actual[field.to_s] || actual[field]
        {
          compared: true,
          matched: equal?(field, expected_value, actual_value),
          expected: expected_value,
          actual: actual_value
        }
      end

      def equal?(field, expected_value, actual_value)
        expected_norm = normalize(field, expected_value)
        actual_norm = normalize(field, actual_value)
        !blank?(actual_norm) && expected_norm == actual_norm
      end

      # Normalization is case/space/accent-insensitive for text, tolerant to
      # currency formatting for amounts so 50.000 / "50.000" / 50000 are the
      # same amount, and canonical for dates regardless of input format.
      def normalize(field, value)
        case field
        when :amount
          amount_to_decimal(value)
        when :date
          date_to_iso(value)
        when :currency
          value.to_s.upcase.squish
        else
          text_normalize(value)
        end
      end

      def amount_to_decimal(value)
        return value if value.is_a?(Numeric)

        text = value.to_s.strip
        return nil if text.blank?

        # dot thousands + optional comma decimals: 12.500,50 -> 12500.50
        if text.match?(/\A-?\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?\z/)
          text = text.delete(".").gsub(",", ".")
        # comma thousands: 20,000 -> 20000
        elsif text.match?(/\A-?\d{1,3}(?:,\d{3})+\z/)
          text = text.delete(",")
        # decimal comma: 20,50 -> 20.50
        elsif text.match?(/\A-?\d+,\d{1,2}\z/)
          text = text.tr(",", ".")
        end

        BigDecimal(text)
      rescue ArgumentError, TypeError
        nil
      end

      def date_to_iso(value)
        return nil if value.blank?

        date = Date.iso8601(value.to_s) rescue Date.parse(value.to_s)
        date.iso8601
      rescue ArgumentError, Date::Error, TypeError
        nil
      end

      def text_normalize(value)
        value.to_s.downcase.gsub(/[.¡!¿?+=]/m, " ").gsub(/\s+/, " ").strip
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end