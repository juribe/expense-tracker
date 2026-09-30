# frozen_string_literal: true

module MoneySources
  # Maintains money_sources.cached_balance incrementally.
  #
  # adjust! adds a signed delta to the source that owns the movement (and to
  # its parent when the source is a debit_card, because debit cards roll their
  # spending into the parent account). rebuild! recomputes the balance from
  # scratch — used by the backfill rake task to repair any drift.
  #
  #   MoneySources::BalanceSync.adjust!(source, -250)
  #   MoneySources::BalanceSync.rebuild!(source)
  class BalanceSync
    class << self
      def adjust!(source, delta)
        return if source.nil? || delta.zero?

        delta = delta.to_d
        # Debit cards are not independent: their movements live on the parent.
        targets = source.debit_card? && source.parent ? [ source.parent ] : [ source ]

        MoneySource.where(id: targets.map(&:id))
                   .update_all(<<~SQL)
          cached_balance = cached_balance + #{delta.to_s("F")}
        SQL
      end

      def rebuild!(source)
        base = source.starting_balance.to_d
        tx_sum = Transaction.where(money_source_id: source.id).sum(:amount).to_d
        child_ids = source.children.ids
        child_sum = child_ids.empty? ? 0.to_d : Transaction.where(money_source_id: child_ids).sum(:amount).to_d
        out = Transfer.where(from_source_id: source.id).sum(:amount).to_d
        inn = Transfer.where(to_source_id: source.id).sum(:amount).to_d

        source.update_column(:cached_balance, base + tx_sum + child_sum - out + inn)
      end
    end
  end
end
