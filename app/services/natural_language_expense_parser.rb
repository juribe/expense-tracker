# frozen_string_literal: true

# Single-AI-call natural-language expense parsing. Receives the complete
# free-text input, sends it to the model exactly once, and returns every
# distinct expense the model identified. No separate splitting or
# categorization calls, no merchant recognition, no category creation.
#
#   result = NaturalLanguageExpenseParser.call(text: user_input, current_date: Date.current)
#   result.success?   # => true
#   result.result     # => [ { original_text:, amount:, date:, description:, category:, money_source_hint: }, ... ]
#   result.errors     # => []
#
# The parser does NOT normalize or validate individual expenses; it returns
# the raw entries the model produced (trimmed). Normalization into an
# ExpenseCandidate happens in ExpenseCandidateProcessor.
#
# Pass explicit categories: to authorize the model against a specific set; the
# allowed set can be Category records or plain name strings. When omitted, the
# parser falls back to the user's expense categories (or the application
# defaults when no user is given).
class NaturalLanguageExpenseParser
  DEFAULT_CATEGORIES = I18n.t("categories.defaults.expense").freeze
  attr_accessor :text, :current_date, :user, :categories

  def self.call(text:, current_date: Date.current, user: nil, categories: nil)
    new(text: text, current_date: current_date, user: user, categories: categories).call
  end

  def initialize(text:, current_date:, user: nil, categories: nil)
    @text = text.to_s.strip
    @current_date = current_date.to_date
    @user = user
    @categories = categories
  end

  def call
    return ServiceResult.error([ "Text is empty." ]) if text.blank?

    router_result = Ai::Router.call(
      task: :conversation_expense_parsing,
      input: text,
      context: { user: user, today: current_date, categories: resolved_categories }
    )

    return ServiceResult.error([ router_result.error.presence || "AI parsing failed." ]) unless router_result.ok?

    ServiceResult.success(router_result.data)
  end
end
