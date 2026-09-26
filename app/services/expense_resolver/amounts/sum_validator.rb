# frozen_string_literal: true

module ExpenseResolver
  module Amounts
    # Validates an AI-merged amount against the itemized amounts in the
    # entry's own text ("Almuerzo 72.000 más 10.000 de propina" → 82.000,
    # "Tres cafés de 8.500 cada uno y un sándwich de 22.000" → 47.500).
    # Read-only on the amount: a mismatch only produces the details for a
    # review warning — the model's amount is never rewritten here.
    class SumValidator
      # A "tres cafés de 8.500 cada uno"-style group: quantity (digit or
      # number word), the amount, and "cada uno" confirming per-unit prices.
      MULTIPLIER_REGEX = /
        (?<qty>\d+|(?:#{Service::NUMBER_WORD_ALTERNATION}))
        \s+(?:[a-záéíóúñü]+\s+){0,3}?de\s+
        (?<amount>\d{1,3}(?:['.,]\s?\d{3})+|\d+(?:[.,]\d+)?)
        \s+cada\s+uno
      /xi.freeze

      MIN_ITEMIZED_AMOUNTS = 2

      Result = Struct.new(:model_amount, :expected_total, keyword_init: true) do
        def mismatch?
          expected_total.present?
        end
      end

      def self.call(amount:, text:)
        new(amount: amount, text: text).call
      end

      def initialize(amount:, text:)
        @amount = amount
        @text = text.to_s
      end

      def call
        return Result.new unless itemized?

        value = normalized_model_amount
        return Result.new if value.nil?

        matched = value == expected_total ||
                  contributions.any? { |contribution| value == contribution }

        matched ? Result.new : Result.new(model_amount: value, expected_total: expected_total)
      end

      private

      # Quantity-multiplier groups ("tres cafés de 8.500 cada uno") weigh
      # qty × value; the amounts they contain are not counted again.
      def contributions
        @contributions ||= begin
          list = []
          multiplier_groups.each do |match|
            count = multiplier_count(match)
            value, = Service.interpret_amount(match[:amount], colloquial: true)
            next unless count.positive? && value&.positive?

            list << value * count
          end

          Service.scan_amounts(@text).each do |scan|
            next if multiplier_groups.any? { |match| span_contains?(match, scan) }

            value, = Service.interpret_amount(scan[:raw], colloquial: true)
            list << value if value&.positive?
          end

          list
        end
      end

      def multiplier_count(match)
        qty = match[:qty]
        qty.match?(/\A\d+\z/) ? qty.to_i : Service::NUMBER_WORDS[qty.downcase].to_i
      end

      def multiplier_groups
        @multiplier_groups ||= begin
          groups = []
          position = 0
          while (match = MULTIPLIER_REGEX.match(@text, position))
            groups << match
            position = match.end(0)
          end
          groups
        end
      end

      def span_contains?(match, scan)
        scan[:start] >= match.begin(0) && scan[:end] <= match.end(0)
      end

      def expected_total
        @expected_total ||= contributions.sum(&:to_d)
      end

      def normalized_model_amount
        case @amount
        when Numeric then @amount.positive? ? @amount.to_d : nil
        when String
          parsed, = Service.interpret_amount(@amount, colloquial: true)
          parsed&.positive? ? parsed : nil
        end
      rescue RangeError, ArgumentError, TypeError
        nil
      end

      def itemized?
        Service.scan_amounts(@text).map { |scan| scan[:raw] }.uniq.size >= MIN_ITEMIZED_AMOUNTS
      end
    end
  end
end
