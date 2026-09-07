# frozen_string_literal: true

module TransactionRules
  # Deterministic rule suggestions derived from a user's transaction history —
  # no AI. Two kinds:
  #
  #   1. `pattern`: a merchant text appears in >= 5 transactions AND >= 90%
  #      share the same category => suggest <merchant> -> <category>.
  #   2. `correction`: a merchant was repeatedly manually corrected to the same
  #      category (>= 3 corrections) => suggest "Always categorize X as Y?".
  #
  # Corrections are tracked by transactions whose category differs from the one
  # set by the originating rule, or simply by repeat appearance in a category.
  #
  #   TransactionRules::SuggestionService.new(user).suggestions
  class SuggestionService
    PATTERN_MIN_TRANSACTIONS = 5
    PATTERN_MIN_SHARE = 0.9
    CORRECTION_MIN_COUNT = 3

    def initialize(user)
      @user = user
    end

    def suggestions
      pattern_suggestions + correction_suggestions
    end

    private

    def pattern_suggestions
      grouped = expense_merchants
      grouped.filter_map do |text, rows|
        next if text.blank?

        counts = rows.group_by(&:category_id)
        top_category_id, top_rows = counts.max_by { |_, v| v.size }
        top_count = top_rows.size
        next if top_count < PATTERN_MIN_TRANSACTIONS

        share = top_count.to_f / rows.size
        next if share < PATTERN_MIN_SHARE

        category = Category.find_by(id: top_category_id)
        next if category.nil?

        {
          kind: :pattern,
          merchant: text,
          category: category,
          count: rows.size,
          share: share
        }
      end
    end

    def correction_suggestions
      grouped = expense_merchants
      grouped.filter_map do |text, rows|
        next if text.blank?

        counts = rows.group_by(&:category_id)
        top_category_id, top_rows = counts.max_by { |_, v| v.size }
        top_count = top_rows.size
        next if top_count < CORRECTION_MIN_COUNT

        category = Category.find_by(id: top_category_id)
        next if category.nil?

        {
          kind: :correction,
          merchant: text,
          category: category,
          count: top_count
        }
      end
    end

    def expense_merchants
      @user.expenses
           .where.not(description: [ nil, "" ])
           .group_by { |t| t.description.to_s.strip.downcase }
    end
  end
end
