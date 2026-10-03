# frozen_string_literal: true

module MoneySources
  # OutstandingSync
  # Keeps credit_account.outstanding_balance aligned for revolving loans
  # (crédito rotativo). Using the line — purchases/disbursements recorded as
  # transactions against the loan itself — raises the debt; reversing those
  # transactions lowers it. This is the loan-side mirror of what
  # Payments::BalanceEffect does for payments (which lower the same number)
  # and of the card path when purchases raise the card's cached balance.
  #
  #   MoneySources::OutstandingSync.adjust!(source, 4_000_000)
  #   MoneySources::OutstandingSync.backfill!(source)
  class OutstandingSync
    class << self
      def adjust!(source, delta)
        new(source, delta).adjust!
      end

      # Replays every usage transaction already recorded against the line so
      # sources that predate the usage rule reach the correct outstanding.
      # Idempotent: marked on the credit account, so re-runs never apply the
      # same usage twice.
      def backfill!(source)
        return unless source.loan? && source.sub_kind == "revolving"

        credit_account = source.credit_account
        return if credit_account.nil? || credit_account.outstanding_usage_replayed?

        delta = source.transactions.where(kind: "expense").sum(:amount).to_d.abs
        adjust!(source, delta)
        credit_account.update_column(:outstanding_usage_replayed, true)
      end
    end

    def initialize(source, delta)
      @source = source
      @delta = delta.to_d
    end

    def adjust!
      return if @source.nil? || @delta.zero?
      return unless revolving_loan?

      credit_account = @source.credit_account
      return if credit_account.nil?

      # Atomic increment: two adjustments in one write (reassignment across
      # the same source) must not read a stale in-memory value.
      CreditAccount.where(id: credit_account.id).update_all(<<~SQL)
        outstanding_balance = GREATEST(outstanding_balance + #{@delta.to_s("F")}, 0)
      SQL
    end

    private

    # Only revolving lines can be used (disbursed/purchased against); the
    # other loan sub-types never take usage expenses.
    def revolving_loan?
      @source.loan? && @source.sub_kind == "revolving"
    end
  end
end
