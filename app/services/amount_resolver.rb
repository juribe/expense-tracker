# frozen_string_literal: true

# Resolves an expense amount by comparing the AI's hint against the value the
# application can derive from the user's original text. Mirrors
# CategoryResolver: the text (ownable truth) is the authority, and the AI hint
# wins only when no heuristic match exists.
#
#   result = AmountResolver.call(amount: amount, text: text)
#   result = AmountResolver.call(amount: amount, text: text, currency: "COP")
#   result.amount             # => resolved value (heuristic-first, else AI)
#   result.amount_label       # => raw string that produced the value
#   result.suggested_amount   # => the AI amount kept as a hint when the text
#                              #    disagrees with it (nil when none)
#   result.suggestion?        # => true when the text could not confirm the AI
#
# The heuristic is ExpenseParser::AmountService, which owns all the
# "50 mil" / "50 lucas" / grouped-thousands / medio millón calculations; we
# take its highest-confidence scan of the original text as the resolved value.
#
# Validations surface as a nil amount (the caller's candidate then turns
# invalid). Never persists anything.
class AmountResolver
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
      ExpenseParser::AmountService.scan_amounts(text).each do |scan|
        value, confidence = ExpenseParser::AmountService.interpret_amount(scan[:raw])
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

  def string_amount(value)
    parsed, = ExpenseParser::AmountService.interpret_amount(value)
    parsed&.positive? ? parsed : nil
  end
end
