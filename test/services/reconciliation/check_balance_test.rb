# frozen_string_literal: true

require "test_helper"

module Reconciliation
  # CheckBalance + MoneySources::BalanceAdjust: recording the real balance,
  # resolving ok/difference, the no-transaction balance adjustment, and
  # "Dejar pendiente".
  class CheckBalanceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(
        name: "Cuadre Balance User",
        email: "reconciliation_balance_test@example.com",
        password: "password123"
      )
      @source = MoneySource.create!(user: @user, name: "Davibank Ahorros", kind: "account", starting_balance: 8_400_000)
      @card = MoneySource.create!(user: @user, name: "TC Davibank", kind: "credit_card", starting_balance: 0)
      CreditAccount.create!(money_source: @card, credit_limit: 8_000_000)
    end

    test "matching balance resolves as ok" do
      result = CheckBalance.call(user: @user, money_source: @source, actual_balance: "8400000")

      assert_equal "ok", result.snapshot.resolution
      assert_equal 0.to_d, result.difference
      assert_equal "8400000.0", result.app_balance.to_s
    end

    test "different balance resolves as difference without touching the balance" do
      result = CheckBalance.call(user: @user, money_source: @source, actual_balance: "8450000")

      assert_equal "difference", result.snapshot.resolution
      assert_equal "50000.0", result.difference.to_s
      assert_equal 8_400_000.to_d, @source.reload.balance
      assert_equal 0.to_d, @source.balance_offset
    end

    test "adjust rewrites balance_offset and resolves as ok — no transaction created" do
      assert_difference -> { Transaction.count }, 0 do
        CheckBalance.call(user: @user, money_source: @source, actual_balance: "8450000", adjust: true)
      end

      assert_equal 8_450_000.to_d, @source.reload.balance
      assert_equal "50000.0", @source.balance_offset.to_s

      snapshot = ReconciliationSnapshot.for_period(@user, Date.current.strftime("%Y-%m")).last
      assert_equal "ok", snapshot.resolution
    end

    test "adjust creates a value adjustment for the difference" do
      assert_difference -> { BalanceAdjustment.count }, 1 do
        CheckBalance.call(user: @user, money_source: @source, actual_balance: "8450000", adjust: true,
                          note: "Saldo del banco")
      end

      adjustment = BalanceAdjustment.last
      assert_equal @source, adjustment.money_source
      assert_equal 50_000.to_d, adjustment.delta
      assert_equal "Saldo del banco", adjustment.note
    end

    test "balance offset survives BalanceSync.rebuild!" do
      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8450000", adjust: true)

      MoneySources::BalanceSync.rebuild!(@source)

      assert_equal 8_450_000.to_d, @source.reload.balance
    end

    test "adjusting a credit card debt uses the owed magnitude" do
      # The card owes 1,800,000: an expense against it.
      expense = Expense.create!(
        user: @user, description: "Compra", amount: 1_800_000, kind: "expense",
        source: "manual", date: Date.current, money_source: @card,
        category: Category.create!(user: @user, name: "Compras")
      )
      assert_equal 1_800_000.to_d, @card.reload.used_credit

      # Real statement shows only 1,500,000 owed → adjust down by 300,000.
      CheckBalance.call(user: @user, money_source: @card, actual_balance: "1500000", adjust: true)

      assert_equal 1_500_000.to_d, @card.reload.used_credit
      assert_equal "300000.0", @card.balance_offset.to_s
    end

    test "adjusting a credit card with a positive balance lands on the exact owed amount" do
      # Payments above the recorded spending left the card "a favor": the raw
      # balance is positive, so used_credit reads zero.
      @card.update!(starting_balance: 156_676)
      assert_equal 0.to_d, @card.reload.used_credit

      result = CheckBalance.call(user: @user, money_source: @card, actual_balance: "41485", adjust: true)

      assert_equal 41_485.to_d, @card.reload.used_credit
      assert_equal 0.to_d, result.difference
      assert_equal "ok", result.snapshot.resolution
    end

    test "adjusting a credit card with a positive balance to zero clears it" do
      @card.update!(starting_balance: 156_676)

      result = CheckBalance.call(user: @user, money_source: @card, actual_balance: "0", adjust: true)

      assert_equal 0.to_d, @card.reload.used_credit
      assert_equal 0.to_d, @card.reload.balance
      assert_equal 0.to_d, result.difference
      assert_equal "ok", result.snapshot.resolution
    end

    test "a loan is reconciled through its outstanding balance" do
      loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
      loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)

      result = CheckBalance.call(user: @user, money_source: loan, actual_balance: "32000000")

      assert_equal 32_000_000.to_d, result.app_balance
      assert_equal 0.to_d, result.difference
      assert_equal "ok", result.snapshot.resolution
    end

    test "adjusting a loan lands the outstanding balance on the declared value" do
      loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
      loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)

      result = nil
      assert_no_difference -> { Transaction.count } do
        result = CheckBalance.call(user: @user, money_source: loan, actual_balance: "30.500.000",
                                   adjust: true, note: "Saldo del banco")
      end

      assert_equal 30_500_000.to_d, loan.credit_account.reload.outstanding_balance
      assert_equal 0.to_d, result.difference
      assert_equal "ok", result.snapshot.resolution
      assert_equal "Saldo del banco", loan.reload.balance_offset_note
      assert loan.reload.balance_offset_at.present?
      assert_equal 0.to_d, loan.balance_offset
    end

    test "a later payment keeps reducing the adjusted loan outstanding" do
      loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
      loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)
      CheckBalance.call(user: @user, money_source: loan, actual_balance: "30.500.000", adjust: true)

      category = Category.create!(user: @user, name: "Pagos")
      expense = @user.expenses.create!(
        category: category, description: "Cuota carro", amount: 1_000_000,
        kind: "expense", source: "manual", date: Date.current, money_source: @source
      )
      Payment.create!(
        user: @user, expense: expense, money_source: loan,
        amount: 1_000_000, principal_amount: 900_000, interest_amount: 100_000
      )

      assert_equal 29_600_000.to_d, loan.credit_account.reload.outstanding_balance
    end

    test "leave_pending marks the source without resolving the difference" do
      snapshot = LeavePending.call(user: @user, money_source: @source, period: Date.current.strftime("%Y-%m"))

      assert_equal "left_pending", snapshot.resolution

      state = State.call(@user)
      assert_equal "left_pending", state.snapshot["balances"].first["status"]
      assert_equal 1, state.discrepancies_count
    end

    test "mark_ok confirms the current balance without changing anything" do
      assert_no_difference -> { Transaction.count } do
        result = CheckBalance.call(user: @user, money_source: @source, mark_ok: true)

        assert_equal "ok", result.snapshot.resolution
        assert_equal 8_400_000.to_d, result.app_balance
        assert_equal 0.to_d, result.difference
      end

      assert_equal 8_400_000.to_d, @source.reload.balance
      assert_equal 0.to_d, @source.balance_offset
      assert_nil @source.balance_offset_note
    end

    test "adjust stores the optional note and timestamp as the audit trace" do
      CheckBalance.call(
        user: @user, money_source: @source, actual_balance: "8450000",
        adjust: true, note: "Pago por fuera de la app"
      )

      assert_equal 8_450_000.to_d, @source.reload.balance
      assert_equal "Pago por fuera de la app", @source.balance_offset_note
      assert @source.balance_offset_at.present?
    end

    test "adjust without a note clears any previous trace note" do
      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8450000",
                        adjust: true, note: "nota vieja")
      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8400000", adjust: true)

      assert_equal 8_400_000.to_d, @source.reload.balance
      assert_nil @source.balance_offset_note
      assert @source.balance_offset_at.present?
    end

    test "reconciling several times in the same period keeps a single snapshot" do
      period = Date.current.strftime("%Y-%m")

      assert_difference -> { ReconciliationSnapshot.count }, 1 do
        CheckBalance.call(user: @user, money_source: @source, actual_balance: "8450000", adjust: true)
        CheckBalance.call(user: @user, money_source: @source, mark_ok: true)
      end

      snapshot = ReconciliationSnapshot.for_period(@user, period).find_by(money_source: @source)
      assert_equal "ok", snapshot.resolution
      assert snapshot.checked_at.present?
    end
  end
end
