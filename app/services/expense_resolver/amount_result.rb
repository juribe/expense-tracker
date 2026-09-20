# frozen_string_literal: true

module ExpenseResolver
  class AmountResult
    Result = Struct.new(:amount, :amount_label, :suggested_amount) do
      def suggestion?
        suggested_amount.present?
      end
    end

    attr_accessor :amount, :text, :currency

    def self.call(amount:, text:, currency: nil)
      new(amount: amount, text: text, currency: currency).call
    end

    def initialize(amount:, text:, currency: nil)
      self.amount = amount
      self.text = text.to_s
      self.currency = currency
    end

    def call
      heuristic = best_heuristic
      parsed_ai = normalized_ai

      if heuristic
        matches_ai = parsed_ai && heuristic[:value] == parsed_ai
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

    # Highest-confidence amount scan of the original text, or nil.
    def best_heuristic
      @best_heuristic ||= begin
        best = nil
        ExpenseResolver::Amounts::Service.scan_amounts(text).each do |scan|
          value, confidence = ExpenseResolver::Amounts::Service.interpret_amount(scan[:raw])
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
      parsed, = ExpenseResolver::Amounts::Service.interpret_amount(value)
      parsed&.positive? ? parsed : nil
    end
  end
end
