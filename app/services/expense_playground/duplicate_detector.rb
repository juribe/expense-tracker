# frozen_string_literal: true

require "set"

module ExpensePlayground
  # DuplicateDetector
  # Flags candidates that look like duplicates of the user's existing
  # transactions or of other candidates in the same batch. A candidate is a
  # possible duplicate when it shares (date, amount, money source) with an
  # existing expense, or the same (date, amount) with another candidate.
  #
  # Example: ExpensePlayground::DuplicateDetector.new(user: user).flag(candidates)
  class DuplicateDetector
    def initialize(user:)
      @user = user
    end

    # Returns an array of boolean flags aligned with `candidates` and sets
    # `candidate.duplicate` on each ExpenseCandidate. Amounts are compared on
    # their magnitude so the negative expense sign does not matter.
    def flag(candidates)
      existing_keys = existing_transaction_keys
      seen = Hash.new(0)

      candidates.map do |candidate|
        key = signature(candidate)

        seen[key] += 1 if key
        duplicate = existing_keys.include?(key) || (key && seen[key] > 1) || false
        candidate.duplicate = duplicate if candidate.respond_to?(:duplicate=)
        duplicate
      end
    end

    private

    # Only expenses can collide with imported statement rows, and only within a
    # reasonable window (statements rarely import months-old rows).
    def existing_transaction_keys
      @user.transactions.expense.where(date: 1.year.ago..Date.current)
           .pluck(:date, :amount, :money_source_id)
           .map { |date, amount, source_id| key_for(date, amount.abs, source_id) }
           .to_set
    end

    def signature(candidate)
      return nil if candidate.date.blank? || candidate.amount.blank?

      amount = candidate.amount.to_d.abs
      return nil unless amount.positive?

      source_id = candidate.respond_to?(:money_source_id) ? candidate.money_source_id : nil
      key_for(candidate.date.to_date, amount, source_id)
    end

    def key_for(date, amount, source_id)
      [ date, format_decimal(amount), source_id || "unknown" ]
    end

    def format_decimal(value)
      format("%.2f", value.to_d)
    end
  end
end
