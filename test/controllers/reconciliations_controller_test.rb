# frozen_string_literal: true

require "test_helper"

class ReconciliationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Cuadre Page User",
      email: "reconciliation_page_test@example.com",
      password: "password123"
    )
    @category = Category.create!(user: @user, name: "Servicios")
    @template = RecurringTemplate.create!(
      user: @user,
      category: @category,
      kind: "expense",
      description: "Crédito carro",
      amount: 2_818_000,
      frequency: "monthly",
      source: "manual",
      payment_day: 5
    )
    @account = MoneySource.create!(user: @user, name: "Davibank Ahorros", kind: "account", starting_balance: 8_400_000)
  end

  test "GET /reconciliation renders the dashboard for authenticated user" do
    sign_in @user
    get reconciliation_path

    assert_response :success
    assert_select "h1", text: "Día de Cuadre"
    assert_select "h2", text: "Pagos pendientes"
    assert_select "h2", text: "Saldos por conciliar"
    assert_select "li.list-group-item", minimum: 1
    assert_select("button.js-assign-payment", minimum: 1)
    assert_select("button.js-reconcile", minimum: 1)
  end

  test "GET /reconciliation shows the financial cycle badge in the title when cycles are enabled" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.current)
    sign_in @user

    get reconciliation_path

    assert_response :success
    assert_select "[data-testid=cycle-badge]", text: /#{cycle.label}/
    assert_select "[data-testid=cycle-badge]", text: /#{cycle.range_label}/
  end

  test "GET /reconciliation falls back to the calendar month label without a schedule" do
    sign_in @user

    get reconciliation_path

    assert_response :success
    assert_select "[data-testid=cycle-badge]", text: /#{I18n.l(Date.current, format: :month_year)}/
  end

  test "debt-target pending payment shows go-to-account link instead of the assign modal" do
    loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    RecurringTemplate.create!(
      user: @user, category: @category, kind: "expense",
      description: "Cuota carro", amount: 2_818_000, frequency: "monthly",
      source: "manual", payment_day: 5, money_source: loan
    )

    sign_in @user
    get reconciliation_path

    assert_response :success
    li = css_select("li.list-group-item").find do |item|
      item.css("a[href='#{money_source_path(loan)}']").any?
    end
    assert_not_nil li, "debt row should link to the money source page"
    assert_nil li.css("button.js-assign-payment").first
    # the non-debt row keeps the modal button
    assert_select "button.js-assign-payment"
  end

  test "assign_payment rejects a debt-target template even when posted directly" do
    loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    debt_template = RecurringTemplate.create!(
      user: @user, category: @category, kind: "expense",
      description: "Cuota carro", amount: 2_818_000, frequency: "monthly",
      source: "manual", payment_day: 5, money_source: loan
    )
    expense = @user.expenses.create!(
      category: @category, description: "Pago cuota", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current
    )
    sign_in @user
    get reconciliation_path

    post reconciliation_assign_payment_path(debt_template), params: { expense_id: expense.id }

    assert_redirected_to reconciliation_path(period: Date.current.strftime("%Y-%m"))
    assert flash[:alert].present?
    assert_nil expense.reload.recurring_template_id
  end

  test "overall status shows pending count and turns all-set after resolving" do
    sign_in @user
    get reconciliation_path
    assert_response :success
    assert_select ".badge", text: /1 pendiente/

    @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current
    ).tap do |expense|
      Expenses::RecurringAssignment.assign(user: @user, expense_id: expense.id, recurring_template_id: @template.id)
    end
    Reconciliation::CheckBalance.call(user: @user, money_source: @account, actual_balance: "8400000")

    get reconciliation_path
    assert_response :success
    assert_select ".badge", text: /Todo cuadrado/
  end

  test "GET /reconciliation redirects unauthenticated user to sign in" do
    get reconciliation_path
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "sidebar includes the Día de Cuadre link" do
    sign_in @user
    get dashboard_path
    assert_select "a[href='#{reconciliation_path}']"
  end

  test "POST refresh recalculates and persists the state" do
    sign_in @user
    prior = Time.zone.now - 1.minute
    ReconciliationState.create!(
      user: @user, period: Date.current.strftime("%Y-%m"), status: "reconciled",
      pending_payments_count: 0, discrepancies_count: 0, snapshot: {}, checked_at: prior, stale: false
    )

    post reconciliation_refresh_path
    assert_redirected_to reconciliation_path
    assert flash[:notice].present?

    state = ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m"))
    assert_equal 1, state.pending_payments_count
    assert_operator state.checked_at, :>, prior
  end

  test "GET search_expenses returns matching expenses as JSON" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "gmail", date: Date.current
    )
    @user.expenses.create!(
      category: @category, description: "Supermercado", amount: 320_000,
      kind: "expense", source: "manual", date: Date.current
    )
    sign_in @user

    get reconciliation_search_expenses_path, params: { q: "crédito carro", amount: "2818000" }

    assert_response :success
    results = JSON.parse(response.body)["expenses"]
    assert_equal [ expense.id ], results.map { |row| row["id"] }
    assert_equal "2818000.0", results.first["amount"]
  end

  test "search_expenses excludes expenses already linked to a template" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "gmail", date: Date.current
    )
    expense.update!(recurring_template_id: @template.id)
    sign_in @user

    get reconciliation_search_expenses_path, params: { q: "crédito carro" }

    results = JSON.parse(response.body)["expenses"]
    assert_empty results
  end

  test "POST assign_payment links expense to template and refreshes state" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current
    )
    sign_in @user

    assert_difference -> { @template.transactions.count }, 1 do
      post reconciliation_assign_payment_path(@template), params: { expense_id: expense.id }
    end

    assert_redirected_to reconciliation_path(period: Date.current.strftime("%Y-%m"))
    assert_equal expense.reload.recurring_template_id, @template.id
    assert_equal 0, ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m")).pending_payments_count
  end

  test "POST assign_payment with a taken period shows failure" do
    expense_one = @user.expenses.create!(
      category: @category, description: "Pago 1", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current
    )
    expense_two = @user.expenses.create!(
      category: @category, description: "Pago duplicado", amount: 2_800_000,
      kind: "expense", source: "manual", date: Date.current
    )
    Expenses::RecurringAssignment.assign(user: @user, expense_id: expense_one.id, recurring_template_id: @template.id)
    sign_in @user

    post reconciliation_assign_payment_path(@template), params: { expense_id: expense_two.id }

    assert_redirected_to reconciliation_path(period: Date.current.strftime("%Y-%m"))
    assert flash[:alert].present?
  end

  test "POST assign_payment with an expense dated outside the period explains and does not link" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "gmail", date: 1.month.ago.to_date
    )
    sign_in @user
    get reconciliation_path # the user is already on the cuadre page before assigning

    post reconciliation_assign_payment_path(@template), params: { expense_id: expense.id }

    assert_redirected_to reconciliation_path(period: Date.current.strftime("%Y-%m"))
    assert flash[:alert].present?
    assert_nil expense.reload.recurring_template_id
    assert_equal 1, ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m")).pending_payments_count

    # Retrying eventually with a same-period expense must work — no deadlock.
    in_period = @user.expenses.create!(
      category: @category, description: "Pago crédito carro octubre", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current
    )
    post reconciliation_assign_payment_path(@template), params: { expense_id: in_period.id }
    assert_redirected_to reconciliation_path(period: Date.current.strftime("%Y-%m"))
    assert_equal @template.id, in_period.reload.recurring_template_id
    assert_equal 0, ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m")).pending_payments_count
  end

  test "POST assign_payment twice with the same expense stays successful (idempotent retry)" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current
    )
    sign_in @user

    2.times do
      post reconciliation_assign_payment_path(@template), params: { expense_id: expense.id }
      assert_redirected_to reconciliation_path(period: Date.current.strftime("%Y-%m"))
    end

    assert flash[:notice].present?
    assert_equal @template.id, expense.reload.recurring_template_id
    assert_equal 0, ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m")).pending_payments_count
  end

  test "search_expenses only returns expenses dated within the cuadre period" do
    in_period = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "gmail", date: Date.current
    )
    @user.expenses.create!(
      category: @category, description: "Pago crédito carro anterior", amount: 2_818_000,
      kind: "expense", source: "gmail", date: 1.month.ago.to_date
    )
    sign_in @user

    get reconciliation_search_expenses_path, params: { q: "crédito carro" }

    results = JSON.parse(response.body)["expenses"]
    assert_equal [ in_period.id ], results.map { |row| row["id"] }
  end

  test "POST actual_balance with adjust corrects the app balance without a transaction" do
    sign_in @user

    assert_no_difference -> { Transaction.count } do
      post reconciliation_actual_balance_path(@account),
           params: { actual_balance: "8.450.000", adjust: "true" }
    end

    assert_redirected_to reconciliation_path
    assert_equal 8_450_000.to_d, @account.reload.balance
    snapshot = ReconciliationSnapshot.find_by(user: @user, money_source: @account)
    assert_equal "ok", snapshot.resolution
  end

  test "POST actual_balance with mark_ok confirms the balance without changing it" do
    sign_in @user

    assert_no_difference -> { Transaction.count } do
      assert_no_difference -> { @account.reload.balance_offset } do
        post reconciliation_actual_balance_path(@account), params: { mark_ok: "true" }
      end
    end

    assert_redirected_to reconciliation_path
    snapshot = ReconciliationSnapshot.find_by(user: @user, money_source: @account)
    assert_equal "ok", snapshot.resolution
    assert_equal 8_400_000.to_d, snapshot.actual_balance
    state = ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m"))
    assert_equal 0, state.discrepancies_count
    assert_equal 0, state.unverified_count
  end

  test "POST actual_balance with adjust stores the note on the source" do
    sign_in @user

    post reconciliation_actual_balance_path(@account),
         params: { actual_balance: "8.450.000", adjust: "true", note: "Pago por fuera" }

    assert_redirected_to reconciliation_path
    assert_equal "Pago por fuera", @account.reload.balance_offset_note
    assert @account.balance_offset_at.present?
  end

  test "POST leave_pending keeps the row as a discrepancy" do
    @template.update!(active: false) # isolate the balance warning
    sign_in @user

    post reconciliation_leave_pending_path(@account)

    assert_redirected_to reconciliation_path
    snapshot = ReconciliationSnapshot.find_by(user: @user, money_source: @account)
    assert_equal "left_pending", snapshot.resolution
    state = ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m"))
    assert_equal "warning", state.status
  end

  test "reset_adjustment clears the manual balance correction" do
    Reconciliation::CheckBalance.call(user: @user, money_source: @account, actual_balance: "8.450.000",
                                      adjust: true, note: "Pago por fuera")
    assert_equal 8_450_000.to_d, @account.reload.balance
    sign_in @user

    assert_no_difference -> { Transaction.count } do
      post reset_adjustment_money_source_path(@account)
    end

    assert_redirected_to money_source_path(@account)
    assert flash[:notice].present?
    assert_equal 0.to_d, @account.reload.balance_offset
    assert_nil @account.balance_offset_note
    assert_nil @account.balance_offset_at
  end

  test "reset_adjustment redirects unauthenticated user" do
    post reset_adjustment_money_source_path(@account)
    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "new expense form accepts reconciliation prefill params" do
    sign_in @user
    get new_expense_path, params: { amount: "500000", description: "Diferencia Davibank", date: Date.current.iso8601, money_source_id: @account.id }

    assert_response :success
    assert_select "input[value*='500.000']"
  end
end
