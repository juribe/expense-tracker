# frozen_string_literal: true

module TransactionRules
  # Applies a user's enabled rules to a transaction. Idempotent — a rule's
  # actions are only applied once (tracked via Transaction#applied_rule_ids),
  # and blank "manual override" gaps are filled without replacing non-blank
  # values the user has already set.
  #
  #   TransactionRules::Applicator.new(user).apply(transaction)
  class Applicator
    def initialize(user)
      @user = user
    end

  # prefer_rules: for AI-entry expenses the parser's category is a guess, so
  # the first matching rule (by specificity) that sets a category wins and
  # later matching rules never clobber it.
  def apply(transaction, prefer_rules: false)
    return transaction if transaction.nil?
    return transaction unless @user.is_a?(User)

    rules = TransactionRule.active.for_user(@user).ordered_by_specificity.to_a
    category_decided = false
    rules.each do |rule|
      next unless rule.matches?(transaction)

      rule.apply_to(transaction, prefer_rules: prefer_rules && !category_decided)
      category_decided ||= transaction.rule_id == rule.id
    end

      transaction
    end

    # Returns the most specific active rule whose category action matches the
    # transaction, or nil. Used to skip creating parser-suggested categories
    # that a rule will replace anyway.
    def matching_category_rule(transaction)
      return if transaction.nil?
      return unless @user.is_a?(User)

      TransactionRule.active.for_user(@user).ordered_by_specificity
                      .find { |rule| rule.category_id.present? && rule.matches?(transaction) }
    end
  end
end
