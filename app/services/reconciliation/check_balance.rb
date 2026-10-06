# frozen_string_literal: true

module Reconciliation
  # Records the "real" balance the user enters for a source in the Conciliar
  # modal and resolves the check. When the user chooses "Ajustar saldo" the
  # app balance is corrected via MoneySources::BalanceAdjust (never by
  # inventing a "Descuadre" expense — a discrepancy is not necessarily an
  # expense).
  class CheckBalance
    Result = Struct.new(:snapshot, :app_balance, :difference, keyword_init: true)

    class << self
      def call(user:, money_source:, actual_balance: nil, adjust: false, mark_ok: false,
               note: nil, period: Date.current.strftime("%Y-%m"))
        new(user: user, money_source: money_source, actual_balance: actual_balance,
            adjust: adjust, mark_ok: mark_ok, note: note, period: period).call
      end
    end

    def initialize(user:, money_source:, actual_balance:, adjust:, mark_ok:, note:, period:)
      @user = user
      @money_source = money_source
      # "Todo está bien": the balance is left as is and marked reconciled.
      @actual_balance = if mark_ok
        Calculator.reconcilable_balance(money_source)
      else
        MoneyFormat.normalize(actual_balance.to_s).to_s.to_d
      end
      @adjust = adjust
      @mark_ok = mark_ok
      @note = note
      @period = period
    end

    def call
      app_balance = Calculator.reconcilable_balance(@money_source)

      if @adjust && !@mark_ok
        outcome = MoneySources::BalanceAdjust.call(source: @money_source, actual_balance: @actual_balance, note: @note)
        app_balance = outcome[:balance]
      end

      difference = @actual_balance - app_balance
      resolution = difference.zero? ? "ok" : "difference"
      snapshot = ReconciliationSnapshot.upsert_for!(
        user: @user, money_source: @money_source, period: @period,
        actual_balance: @actual_balance, resolution: resolution
      )

      Result.new(snapshot: snapshot, app_balance: app_balance, difference: difference)
    ensure
      # The persisted dashboard state is now outdated until the next
      # recalculation (the controller refreshes right away).
      Reconciliation::Invalidate.call(user_id: @user.id)
    end
  end
end
