# frozen_string_literal: true

module ExpenseResolver
  class AmountResult
    Result = Struct.new(:amount, :amount_label, :suggested_amount) do
      def suggestion?
        suggested_amount.present?
      end
    end

    attr_accessor :amount, :text, :currency, :allow_heuristic

    def self.call(amount:, text:, currency: nil, allow_heuristic: true)
      new(amount: amount, text: text, currency: currency, allow_heuristic: allow_heuristic).call
    end

    def initialize(amount:, text:, currency: nil, allow_heuristic: true)
      self.amount = amount
      self.text = text.to_s
      self.currency = currency
      self.allow_heuristic = allow_heuristic
    end

    def call
      parsed_ai = normalized_ai
      heuristic = allow_heuristic ? best_heuristic : nil

      if heuristic && trusted?(heuristic, parsed_ai)
        matches_ai = parsed_ai && heuristic[:value].to_d == parsed_ai.to_d
        Result.new(
          heuristic[:value],
          heuristic[:raw],
          matches_ai || parsed_ai.nil? ? nil : parsed_ai
        )
      elsif parsed_ai
        Result.new(parsed_ai, amount.to_s, nil)
      else
        Result.new(nil, nil, nil)
      end
    end

    private

    # A scan over shared full-message text (several expenses echoed into one
    # fragment) is ambiguous: the winning value may belong to another expense.
    # The heuristic only overrides the AI amount when the text yields a single
    # value, the AI is absent, or the scan corroborates the AI amount — and a
    # differing override demands a high-confidence read ("50 mil"-style).
    # Low-confidence bare numbers never beat the AI's colloquial reading.
    HIGH_CONFIDENCE_SCAN = 0.85

    def trusted?(heuristic, parsed_ai)
      return true if parsed_ai.nil?
      return true if heuristic[:value].to_d == parsed_ai.to_d
      return false if heuristic[:confidence] < HIGH_CONFIDENCE_SCAN

      distinct_values.one?
    end

    def distinct_values
      @distinct_values ||= scanned_amounts.map(&:to_d).uniq
    end

    def scanned_amounts
      ExpenseResolver::Amounts::Service.scan_amounts(text).filter_map do |scan|
        value, = ExpenseResolver::Amounts::Service.interpret_amount(scan[:raw], colloquial: true)
        value&.positive? ? value : nil
      end
    end

    # Highest-confidence amount scan of the original text, or nil.
    def best_heuristic
      @best_heuristic ||= begin
        best = nil
        ExpenseResolver::Amounts::Service.scan_amounts(text).each do |scan|
          value, confidence = ExpenseResolver::Amounts::Service.interpret_amount(scan[:raw], colloquial: true)
          next unless value&.positive?

          best = { value: value, confidence: confidence, raw: scan[:raw] } if best.nil? || confidence > best[:confidence]
        end
        best
      end
    end

    # Normalizes the AI amount into a positive numeric, or nil.
    def normalized_ai
      return nil if amount.blank?

      case amount
      when Numeric
        amount.positive? ? amount : nil
      when String
        string_amount(amount)
      end
    rescue RangeError, ArgumentError, TypeError
      nil
    end

    def decimal_from_string(value)
      cleaned = value.to_s.delete("$ ,.")
      Integer(cleaned)
    rescue ArgumentError
      Float(value.to_s.delete("$ ,"))
    end

    def string_amount(value)
      parsed, = ExpenseResolver::Amounts::Service.interpret_amount(value, colloquial: true)
      parsed&.positive? ? parsed : nil
    end
  end
end
