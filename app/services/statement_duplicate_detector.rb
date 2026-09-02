# frozen_string_literal: true

# StatementDuplicateDetector
# Compares an extracted statement source against the user's existing
# MoneySource records to surface probable duplicates during import review.
#
# Matches on the user-scoped unique identifier or on (bank + card_last_four),
# mirroring the MoneySource identifier uniqueness rule.
#
# Example: StatementDuplicateDetector.new(user: user).duplicate_of?(statement)
class StatementDuplicateDetector
  def initialize(user:)
    @user = user
  end

  # Returns an existing MoneySource when the statement matches, else nil.
  def duplicate_of?(statement)
    by_identifier(statement) || by_bank_and_last_four(statement)
  end

  private

  def by_identifier(statement)
    return nil if statement.identifier.blank?

    target = statement.identifier.to_s.strip.downcase
    @user.money_sources.find_by("lower(trim(identifier)) = ?", target)
  end

  def by_bank_and_last_four(statement)
    return nil if statement.card_last_four.blank? || statement.bank.blank?

    @user.money_sources
         .joins(:credit_account)
         .where(money_sources: { bank: statement.bank })
         .where(credit_accounts: { card_last_four: statement.card_last_four })
         .first
  end
end
