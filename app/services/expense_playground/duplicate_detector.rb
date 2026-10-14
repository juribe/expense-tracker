# frozen_string_literal: true

require "set"

module ExpensePlayground
  # DuplicateDetector
  # Flags candidates that look like duplicates of the user's existing
  # transactions or of other candidates in the same batch. A candidate is a
  # possible duplicate when it shares (date, amount, money source) with an
  # existing expense, or the same (date, amount) with another candidate.
  #
  # Sets `candidate.duplicate` (true when it should be skipped on confirm) and
  # `candidate.duplicate_kind` (:existing for a match against a recorded
  # expense, :in_statement for a repeat inside the same batch — so the review
  # can highlight every row of a possible double charge).
  #
  # Example: ExpensePlayground::DuplicateDetector.new(user: user).flag(candidates)
  class DuplicateDetector
    def initialize(user:)
      @user = user
    end

    # Returns an array of boolean skip-flags aligned with `candidates` and sets
    # `candidate.duplicate` / `candidate.duplicate_kind` on each
    # ExpenseCandidate. Amounts are compared on their magnitude so the negative
    # expense sign does not matter.
    def flag(candidates)
      existing_keys = existing_transaction_keys
      signatures = candidates.map { |candidate| signature(candidate) }
      counts = signatures.compact.tally
      seen = Hash.new(0)

      candidates.each_with_index.map do |candidate, index|
        key = signatures[index]
        seen[key] += 1 if key
        in_statement = key && counts[key] > 1
        matches_existing = key && existing_keys.include?(key)
        duplicate = matches_existing || (key && seen[key] > 1) || false

        apply(candidate, duplicate: duplicate, kind: duplicate_kind(in_statement, matches_existing))
        duplicate
      end
    end

    private

    def apply(candidate, duplicate:, kind:)
      candidate.duplicate = duplicate if candidate.respond_to?(:duplicate=)
      candidate.duplicate_kind = kind if candidate.respond_to?(:duplicate_kind=)
    end

    # An in-statement repeat wins over an existing-expense match so every row of
    # a possible double charge is highlighted as such.
    def duplicate_kind(in_statement, matches_existing)
      return :in_statement if in_statement
      return :existing if matches_existing

      nil
    end

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
