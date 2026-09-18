# frozen_string_literal: true

# Normalizes a single expense returned by NaturalLanguageExpenseParser into an
# ExpenseCandidate, coercing amount/date into app-native types and resolving
# the AI's category hint through CategoryResolver.
#
#   candidate = ExpenseCandidateProcessor.call(expense: expense, user: user)
#   candidate = ExpenseCandidateProcessor.call(expense: expense, user: user, categories: [ ... ])
#   candidate.valid?   # => false when amount/date could not be normalized
#   candidate.errors   # => [...]
#
# Pass explicit categories: to authorize the resolution against a specific
# set; entries can be Category records or plain name strings. When omitted,
# the processor falls back to the user's expense categories (or the
# application defaults when no user is given).
#
# The category hint is resolved through CategoryResolver, which owns all the
# "is this new?" / "is this a suggestion?" calculations: an unheard-of label
# becomes a suggestion, a match becomes the user's real Category.
#
# Never persists anything.
class ExpenseCandidateProcessor
  attr_accessor :expense, :user, :categories

  def self.call(expense:, user:, categories: nil)
    new(expense: expense, user: user, categories: categories).call
  end

  def initialize(expense:, user:, categories: nil)
    self.expense = (expense.respond_to?(:to_h) ? expense.to_h : expense).transform_keys(&:to_s)
    self.user = user
    self.categories = categories
  end

  def call
    ExpenseCandidate.new(
      amount: amount_result.amount,
      currency: ExpenseCandidate::DEFAULT_CURRENCY,
      category_id: category_result.category&.id,
      category_name: category_result.category_name,
      description: description,
      date: date,
      source: "playground",
      classification_source: "ai",
      suggested_category_name: category_result.suggestion? ? category_result.suggested_category_name : nil,
      money_source_name: money_source_hint
    )
  end

  def amount_result
    @amount_result ||= AmountResolver.call(
      amount: amount,
      text: original_text
    )
  end

  # The resolved (or suggested) category for this expense.
  def category_result
    @category_result ||= CategoryResolver.call(
      expense: expense,
      user: user,
      categories: categories
    )
  end

  private

  def description
    expense["description"].to_s.strip.presence || expense["original_text"].to_s.strip.presence
  end

  def amount
    value = expense["amount"]
    parsed =
      case value
      when Numeric then value
      when String then decimal_from_string(value)
      end
    parsed&.round
  rescue RangeError, ArgumentError
    nil
  end

  def decimal_from_string(value)
    cleaned = value.to_s.delete("$ ,.")
    Integer(cleaned)
  rescue ArgumentError
    Float(value.to_s.delete("$ ,"))
  end

  def date
    string = expense["date"].to_s.strip.sub(/T.*/, "")
    return nil if string.blank?

    Date.parse(string)
  rescue ArgumentError, TypeError
    nil
  end

  def money_source_hint
    expense["money_source_hint"].to_s.strip.presence
  end
end
