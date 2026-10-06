# frozen_string_literal: true

module MoneySources
  # "Ajustar saldo" from the Día de Cuadre dashboard: makes the app balance
  # match the real balance WITHOUT creating an expense or income. The
  # correction is stored in money_sources.balance_offset, which is part of
  # MoneySource#balance and survives BalanceSync.rebuild! recomputes.
  #
  # The adjustment is silent by design but not anonymous: the optional note
  # and the timestamp give the money source page an auditable trace of the
  # last manual correction.
  class BalanceAdjust
    class << self
      def call(source:, actual_balance:, note: nil)
        actual = actual_balance.to_d
        current = Reconciliation::Calculator.reconcilable_balance(source)
        delta = actual - current

        # For credit cards the reconciled magnitude is the debt: owing MORE
        # means the (negative) balance moves further down.
        offset_delta = source.credit_card? ? -delta : delta

        source.assign_attributes(
          balance_offset_note: note.presence,
          balance_offset_at: Time.current
        )
        source.balance_offset += offset_delta
        source.save!

        { balance: Reconciliation::Calculator.reconcilable_balance(source.reload), delta: offset_delta }
      end
    end
  end
end
