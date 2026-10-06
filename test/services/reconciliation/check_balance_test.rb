# frozen_string_literal: true

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

    test "leave_pending marks the source without resolving the difference" do
      snapshot = LeavePending.call(user: @user, money_source: @source, period: Date.current.strftime("%Y-%m"))

      assert_equal "left_pending", snapshot.resolution
      assert_equal "8400000.0", snapshot.actual_balance.to_s

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
  end
end
