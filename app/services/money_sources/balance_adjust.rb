# frozen_string_literal: true

module MoneySources
  # "Ajustar saldo" from the Día de Cuadre dashboard: makes the reconciled
  # balance match the real balance WITHOUT creating an expense or income.
  #
  # - Accounts, cash, wallets and cards: the correction is stored in
  #   money_sources.balance_offset, which is part of MoneySource#balance and
  #   survives BalanceSync.rebuild! recomputes.
  # - Loans: the debt lives on credit_account.outstanding_balance, so the
  #   manual adjustment lands there (clamped at zero, same as
  #   Payments::BalanceEffect); later payments keep reducing it from the
  #   adjusted value.
  #
  # The adjustment is silent by design but not anonymous: the optional note
  # and the timestamp give the money source page an auditable trace of the
  # last manual correction.
  class BalanceAdjust
    class << self
      def call(source:, actual_balance:, note: nil)
        actual = actual_balance.to_d
        current = Reconciliation::Calculator.reconcilable_balance(source)

        source.assign_attributes(
          balance_offset_note: note.presence,
          balance_offset_at: Time.current
        )

        delta =
          if source.loan?
            adjust_loan(source, actual, current)
          else
            adjust_offset(source, actual, current)
          end
        source.save!

        if delta.to_d.nonzero?
          BalanceAdjustment.create!(
            user: source.user,
            money_source: source,
            effective_date: Time.current.to_date,
            delta: delta,
            note: note.presence
          )
        end

        { balance: Reconciliation::Calculator.reconcilable_balance(source.reload), delta: delta }
      end

      private

      def adjust_offset(source, actual, current)
        # For credit cards the reconciled magnitude is the owed amount, so the
        # raw balance must land exactly on -actual. With debt stored as a
        # negative balance this equals the used-credit delta; it also absorbs a
        # positive (saldo a favor) balance left by payments above the recorded
        # spending, which used_credit alone would clamp to zero.
        delta = source.credit_card? ? -actual - source.balance : actual - current
        source.balance_offset += delta
        delta
      end

      def adjust_loan(source, actual, current)
        credit_account = source.credit_account
        return actual - current if credit_account.nil?

        credit_account.update_column(:outstanding_balance, [ actual, 0.to_d ].max)
        actual - current
      end
    end
  end
end
