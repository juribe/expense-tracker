# frozen_string_literal: true

module ExpensePlayground
  # Compares an ExpenseCandidate against a user-provided expected result.
  # This is the hook for the playground's test/evaluation capability and for
  # a future regression suite over recorded runs.
  #
  #   Evaluation.new(
  #     candidate: candidate,
  #     expected: { amount: 50000, category: "food", description: "almuerzos" }
  #   ).result
  #     => { checks: [ { field:, expected:, actual:, passed: } ],
  #          passed: 2, total: 2, ok?: true }
  class Evaluation
    FIELDS = %i[amount category description merchant date source].freeze

    def self.call(candidate:, expected:)
      new(candidate: candidate, expected: expected).result
    end

    def initialize(candidate:, expected:)
      @candidate = candidate
      @expected = symbolize(expected)
    end

    def result
      checks = FIELDS.filter_map { |field| check_for(field) }
      passed = checks.count { |check| check[:passed] }
      {
        checks: checks,
        passed: passed,
        total: checks.length,
        ok?: passed == checks.length && !checks.empty?
      }
    end

    private

    def symbolize(expected)
      hash = (expected.respond_to?(:to_unsafe_h) ? expected.to_unsafe_h : expected) || {}
      hash.deep_symbolize_keys
    end

    def check_for(field)
      expected_value = @expected[field]
      return nil if expected_value.blank?

      { field: field, expected: expected_value.to_s, actual: actual_for(field), passed: matches?(field, expected_value) }
    end

    def actual_for(field)
      candidate = @candidate
      value =
        case field
        when :amount then candidate&.amount
        when :category then candidate&.category_name
        when :description then candidate&.description
        when :merchant then candidate&.merchant
        when :date then candidate&.date&.iso8601
        when :source then candidate&.money_source_name
        end
      value.to_s
    end

    def matches?(field, expected_value)
      candidate = @candidate
      case field
      when :amount
        expected_amount = parse_amount(expected_value)
        actual_amount = candidate.amount.is_a?(Numeric) ? BigDecimal(candidate.amount.to_s) : nil
        actual_amount.present? && expected_amount.present? &&
          (actual_amount - expected_amount).abs < BigDecimal("0.01")
      when :category
        normalize(candidate&.category_name) == normalize(expected_value)
      when :description
        normalized = normalize(candidate&.description)
        expected = normalize(expected_value)
        normalized.present? && (normalized.include?(expected) || expected.include?(normalized))
      when :merchant
        actual = normalize(candidate&.merchant)
        expected_merchant = normalize(expected_value)
        actual.present? && (actual.include?(expected_merchant) || expected_merchant.include?(actual))
      when :date
        candidate_date = candidate&.date
        expected_date = begin
          Date.iso8601(expected_value.to_s)
        rescue ArgumentError, Date::Error, TypeError
          nil
        end
        candidate_date.present? && expected_date.present? && candidate_date == expected_date
      when :source
        actual = normalize(candidate&.money_source_name)
        expected_source = normalize(expected_value)
        actual.present? && (actual.include?(expected_source) || expected_source.include?(actual))
      else
        false
      end
    end

    def parse_amount(value)
      return BigDecimal(value.to_s) if value.is_a?(Numeric)
      return nil if value.to_s.strip.blank?

      text = value.to_s.strip.downcase
      multiplier = 1
      if (match = text.match(/\A\d+(?:[.,]\d+)?\s*(mil|k)\z/))
        multiplier = 1000
        text = match[0].sub(/(mil|k)\z/, "").strip
      end
      BigDecimal(text.delete(",")) * multiplier
    rescue ArgumentError, TypeError
      nil
    end

    def normalize(text)
      text.to_s.downcase.tr("áéíóúü", "aeiouu").squish
    end
  end
end
