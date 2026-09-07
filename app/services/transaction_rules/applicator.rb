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

    def apply(transaction)
      return transaction if transaction.nil?
      return transaction unless @user.is_a?(User)

      rules = TransactionRule.active.for_user(@user).ordered_by_specificity.to_a
      rules.each do |rule|
        rule.apply_to(transaction) if rule.matches?(transaction)
      end

      transaction
    end
  end
end
