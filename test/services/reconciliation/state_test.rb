# frozen_string_literal: true

require "test_helper"

module Reconciliation
  # State + Calculator: pending recurring payments, balance discrepancy rows,
  # status derivation, staleness invalidation and persistence.
  class StateTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(
        name: "Cuadre User",
        email: "reconciliation_state_test@example.com",
        password: "password123"
      )
      @category = Category.create!(user: @user, name: "Servicios")
      @source = MoneySource.create!(user: @user, name: "Davibank", kind: "account", starting_balance: 8_400_000)
      @template = RecurringTemplate.create!(
        user: @user,
        category: @category,
        kind: "expense",
        description: "Internet",
        amount: 180_000,
        frequency: "monthly",
        source: "manual",
        payment_day: 7
      )
    end

    def build_expense(attributes = {})
      Expense.create!(
        {
          user: @user,
          category: @category,
          description: "Pago Internet",
          amount: 180_000,
          kind: "expense",
          source: "manual",
          date: Date.current
        }.merge(attributes)
      )
    end

    test "recalculates pending payments for period and persists state" do
      state = State.call(@user)

      assert_equal 1, state.pending_payments_count
      assert_equal "pending", state.status
      assert_equal "Internet", state.snapshot["pending_payments"].first["name"]
      assert_not state.snapshot["pending_payments"].first["debt"]
      assert_not state.stale?
      assert state.checked_at.present?
    end

    test "a persisted state built before the current snapshot shape is recalculated" do
      state = State.refresh!(@user)
      state.update!(snapshot: state.snapshot.except("version"), stale: false) # old shape, not stale

      # Old snapshots render debt rows without the money-source action, so the
      # dashboard must transparently rebuild them.
      reloaded = State.call(@user)

      assert_equal Calculator::SNAPSHOT_VERSION, reloaded.snapshot["version"]
      assert_equal [ "Internet" ], reloaded.snapshot["pending_payments"].map { |row| row["name"] }
      refute reloaded.snapshot["pending_payments"].first["debt"]
    end

    test "debt-target pending payments are flagged so the cuadre offers the money source" do
      loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
      debt_template = RecurringTemplate.create!(
        user: @user,
        category: @category,
        kind: "expense",
        description: "Cuota carro",
        amount: 2_818_000,
        frequency: "monthly",
        source: "manual",
        payment_day: 5,
        money_source: loan
      )

      state = State.call(@user)

      row = state.snapshot["pending_payments"].find { |pending| pending["template_id"] == debt_template.id }
      assert row["debt"]
      assert_equal loan.id, row["money_source_id"]
    end

    test "pending payment disappears once an expense is assigned to the template" do
      expense = build_expense
      result = Expenses::RecurringAssignment.assign(user: @user, expense_id: expense.id, recurring_template_id: @template.id)
      assert result.success?

      # Verify the only source too, so nothing is left unverified.
      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8400000")

      state = State.call(@user)
      assert_equal 0, state.pending_payments_count
      assert_equal "reconciled", state.status
    end

    test "wrong-kind recurring template never shows as pending payment" do
      RecurringTemplate.create!(
        user: @user,
        category: @category,
        kind: "income",
        description: "Salario",
        amount: 5_000_000,
        frequency: "monthly",
        source: "manual"
      )

      state = State.call(@user)
      assert_equal [ "Internet" ], state.snapshot["pending_payments"].map { |row| row["name"] }
    end

    test "balance check with different actual balance produces warning status" do
      @template.update!(active: false) # no pending payments → only balance matters
      State.call(@user) # seed a fresh state first

      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8.450.000")
      State.refresh!(@user)

      state = ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m"))
      row = state.snapshot["balances"].first
      assert_equal "difference", row["status"]
      assert_equal "50000.0", BigDecimal(row["difference"]).to_s
      assert_equal "warning", state.status
    end

    test "balance check with matching actual balance is reconciled" do
      @template.update!(active: false) # no pending payments → only balance matters
      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8400000")

      state = State.call(@user)
      assert_equal "ok", state.snapshot["balances"].first["status"]
      assert_equal "reconciled", state.status
    end

    test "unverified sources are counted and block the reconciled status" do
      state = State.call(@user)
      assert_equal "unverified", state.snapshot["balances"].first["status"]
      assert_equal 1, state.unverified_count
      assert_equal "pending", state.status

      # Verifying the balance clears it.
      @template.update!(active: false)
      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8400000")

      state = State.call(@user)
      assert_equal 0, state.unverified_count
      assert_equal "reconciled", state.status
    end

    test "explicit refresh updates checked_at and clears staleness" do
      stale_before = State.call(@user).checked_at

      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8.450.000")
      assert ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m")).reload.stale?

      State.refresh!(@user)
      state = ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m"))
      assert_not state.stale?
      assert_operator state.checked_at, :>=, stale_before
      assert_equal 1, state.discrepancies_count
    end

    test "status precedence: pending payments beat balance warnings" do
      CheckBalance.call(user: @user, money_source: @source, actual_balance: "8.450.000")

      state = State.call(@user)
      assert_equal "pending", state.status
      assert state.pending_payments_count.positive?
      assert_equal 1, state.discrepancies_count
    end
  end
end
