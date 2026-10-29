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
    @recon_source = @user.money_sources.create!(name: "Cuenta", kind: "account", active: false, starting_balance: 1_000_000_000)
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
    assert_select "h1", text: /Día de Balance/
    assert_select "h2", text: /Verifica tus saldos/
    assert_select "h3", text: "Saldos de tus cuentas"
    assert_select "h3", text: "Pagos recurrentes sin pagar"
    assert_select "h2", text: /Confirma tus deudas/
    assert_select "h3", text: "Obligaciones por verificar"
    assert_select "li.list-group-item", minimum: 1
    assert_select("button.js-assign-payment", minimum: 1)
    assert_select("button.js-reconcile", minimum: 2)
    assert_select ".rec-hero"
    assert_select ".rec-metrics"
    assert_select "#reconciliationGuideModal"
    assert_select "#reconcileModal #reconcileSearchResults"
    assert_select "#reconcileModal #reconcileLoadMore"
  end

  test "GET /reconciliation balance rows omit the real balance and difference and say Pendiente" do
    sign_in @user
    get reconciliation_path

    assert_response :success
    row = css_select("li.list-group-item").find { |item| item.text.include?(@account.name) }
    assert_not_nil row, "the account row should be rendered"
    assert_includes row.text, "Por verificar"
    assert_includes row.text, "Verificar saldo"
    assert_includes row.text, "Movimientos"
    refute_includes row.text, "Saldo real"
    refute_includes row.text, "Diferencia"
    refute_includes row.text, "Sin verificar"
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
      kind: "expense", source: "manual", date: Date.current,
    money_source: @recon_source)
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
      kind: "expense", source: "manual", date: Date.current, money_source: @recon_source
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

  test "sidebar includes the Día de Balance link" do
    sign_in @user
    get dashboard_path
    assert_select "a[href='#{reconciliation_path}']"
  end

  test "GET search_expenses returns matching expenses as JSON" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "gmail", date: Date.current,
    money_source: @recon_source)
    @user.expenses.create!(
      category: @category, description: "Supermercado", amount: 320_000,
      kind: "expense", source: "manual", date: Date.current,
    money_source: @recon_source)
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
      kind: "expense", source: "gmail", date: Date.current,
    money_source: @recon_source)
    expense.update!(recurring_template_id: @template.id)
    sign_in @user

    get reconciliation_search_expenses_path, params: { q: "crédito carro" }

    results = JSON.parse(response.body)["expenses"]
    assert_empty results
  end

  test "POST assign_payment links expense to template and refreshes state" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current,
    money_source: @recon_source)
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
      kind: "expense", source: "manual", date: Date.current,
    money_source: @recon_source)
    expense_two = @user.expenses.create!(
      category: @category, description: "Pago duplicado", amount: 2_800_000,
      kind: "expense", source: "manual", date: Date.current,
    money_source: @recon_source)
    Expenses::RecurringAssignment.assign(user: @user, expense_id: expense_one.id, recurring_template_id: @template.id)
    sign_in @user

    post reconciliation_assign_payment_path(@template), params: { expense_id: expense_two.id }

    assert_redirected_to reconciliation_path(period: Date.current.strftime("%Y-%m"))
    assert flash[:alert].present?
  end

  test "POST assign_payment with an expense dated outside the period explains and does not link" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "gmail", date: 1.month.ago.to_date,
      money_source: @recon_source)
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
      kind: "expense", source: "manual", date: Date.current,
    money_source: @recon_source)
    post reconciliation_assign_payment_path(@template), params: { expense_id: in_period.id }
    assert_redirected_to reconciliation_path(period: Date.current.strftime("%Y-%m"))
    assert_equal @template.id, in_period.reload.recurring_template_id
    assert_equal 0, ReconciliationState.for_period(@user, Date.current.strftime("%Y-%m")).pending_payments_count
  end

  test "POST assign_payment twice with the same expense stays successful (idempotent retry)" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current,
    money_source: @recon_source)
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
      kind: "expense", source: "gmail", date: Date.current,
    money_source: @recon_source)
    @user.expenses.create!(
      category: @category, description: "Pago crédito carro anterior", amount: 2_818_000,
      kind: "expense", source: "gmail", date: 1.month.ago.to_date,
      money_source: @recon_source)
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

  test "POST actual_balance on a loan updates its outstanding balance" do
    loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)
    sign_in @user

    post reconciliation_actual_balance_path(loan),
         params: { actual_balance: "30.500.000", adjust: "true" }

    assert_redirected_to reconciliation_path
    assert_equal 30_500_000.to_d, loan.credit_account.reload.outstanding_balance
    snapshot = ReconciliationSnapshot.find_by(user: @user, money_source: loan)
    assert_equal "ok", snapshot.resolution
  end

  test "reset_adjustment on a loan clears the trace and keeps the adjusted outstanding" do
    loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)
    Reconciliation::CheckBalance.call(user: @user, money_source: loan, actual_balance: "30.500.000",
                                      adjust: true, note: "Saldo del banco")
    sign_in @user

    post reset_adjustment_money_source_path(loan)

    assert_redirected_to money_source_path(loan)
    assert_equal 30_500_000.to_d, loan.credit_account.reload.outstanding_balance
    assert_nil loan.reload.balance_offset_note
    assert_nil loan.balance_offset_at
  end

  test "POST actual_balance with a pay cycle stores the snapshot under the cycle period" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.current)
    sign_in @user

    post reconciliation_actual_balance_path(@account),
         params: { actual_balance: "8.400.000", adjust: "true" }

    assert_redirected_to reconciliation_path
    snapshot = ReconciliationSnapshot.find_by(user: @user, money_source: @account)
    assert_equal cycle.starts.iso8601, snapshot.period
    assert_equal "ok", snapshot.resolution
  end

  test "dashboard shows the reconciled row instead of Pendiente when cycles are enabled" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.current)
    sign_in @user

    post reconciliation_actual_balance_path(@account),
         params: { actual_balance: "8.400.000", adjust: "true" }
    get reconciliation_path(period: cycle.starts.iso8601)

    assert_response :success
    row = css_select("li.list-group-item").find { |item| item.text.include?(@account.name) }
    assert_not_nil row, "the account row should be rendered"
    assert_includes row.text, "Verificada"
    assert_includes row.text, "Cambiar saldo"
    refute_includes row.text, "Por verificar"
  end

  test "POST leave_pending works with a pay cycle period" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(@user, Date.current)
    sign_in @user

    post reconciliation_leave_pending_path(@account)

    assert_redirected_to reconciliation_path
    snapshot = ReconciliationSnapshot.find_by(user: @user, money_source: @account)
    assert_equal cycle.starts.iso8601, snapshot.period
    assert_equal "left_pending", snapshot.resolution
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

  test "search_expenses filters results by the recurring template category" do
    other_category = Category.create!(user: @user, name: "Transporte")
    matching = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @recon_source
    )
    @user.expenses.create!(
      category: other_category, description: "Pago crédito carro transporte", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @recon_source
    )
    sign_in @user

    get reconciliation_search_expenses_path, params: { q: "Pago crédito carro", template_id: @template.id }

    results = JSON.parse(response.body)["expenses"]
    assert_equal [ matching.id ], results.map { |row| row["id"] }
  end

  test "search_expenses matches a numeric query against the amount" do
    matching = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @recon_source
    )
    @user.expenses.create!(
      category: @category, description: "Otro pago", amount: 500_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @recon_source
    )
    sign_in @user

    get reconciliation_search_expenses_path, params: { q: "2818000", template_id: @template.id }

    results = JSON.parse(response.body)["expenses"]
    assert_equal [ matching.id ], results.map { |row| row["id"] }
  end

  test "search_expenses payload includes the open link and category metadata" do
    expense = @user.expenses.create!(
      category: @category, description: "Pago crédito carro", amount: 2_818_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @recon_source
    )
    sign_in @user

    get reconciliation_search_expenses_path, params: { q: "Pago crédito carro", template_id: @template.id }

    row = JSON.parse(response.body)["expenses"].first
    assert_equal edit_expense_path(expense), row["edit_url"]
    assert_equal "expense", row["kind"]
    assert_equal @category.name, row["category_name"]
  end

  test "search_movements returns only movements for the requested source" do
    other_source = MoneySource.create!(user: @user, name: "Otra cuenta", kind: "account", starting_balance: 1_000_000)
    own_movement = @user.expenses.create!(
      category: @category, description: "Movimiento propio", amount: 100_000,
      kind: "expense", source: "manual", date: Date.current, money_source: @account
    )
    @user.expenses.create!(
      category: @category, description: "Movimiento ajeno", amount: 100_000,
      kind: "expense", source: "manual", date: Date.current, money_source: other_source
    )
    sign_in @user

    get reconciliation_search_movements_path, params: { money_source_id: @account.id }

    body = JSON.parse(response.body)
    assert_equal [ own_movement.id ], body["movements"].map { |row| row["id"] }
    assert_equal edit_expense_path(own_movement), body["movements"].first["edit_url"]
    refute body["has_more"]
  end

  test "search_movements paginates with the existing statement pagination" do
    9.times do |index|
      @user.expenses.create!(
        category: @category, description: "Movimiento #{index}", amount: 10_000 + index,
        kind: "expense", source: "manual", date: Date.current, money_source: @account
      )
    end
    sign_in @user

    get reconciliation_search_movements_path,
        params: { money_source_id: @account.id, page: 1, per_page: 5 }

    first_page = JSON.parse(response.body)
    assert_equal 5, first_page["movements"].size
    assert_equal 9, first_page["total_count"]
    assert first_page["has_more"]

    get reconciliation_search_movements_path,
        params: { money_source_id: @account.id, page: 2, per_page: 5 }

    second_page = JSON.parse(response.body)
    assert_equal 4, second_page["movements"].size
    refute second_page["has_more"]
  end

  test "assign modal no longer shows the Gmail sync action" do
    sign_in @user
    get reconciliation_path

    assert_response :success
    assert_select "#assignPaymentModal", text: /Sync Gmail/, count: 0
    assert_select "#assignPaymentModal a[href*='gmail']", count: 0
  end

  test "pending payment rows use the recurring category icon" do
    @category.update!(icon: "ti-bus")
    sign_in @user

    get reconciliation_path

    assert_response :success
    assert_select "[data-testid='pending-payment-row'] i.ti-bus"
  end

  test "debt sources render in the obligations section with debt-specific labels" do
    loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)
    sign_in @user

    get reconciliation_path

    assert_response :success
    debt_row = css_select("[data-testid='debt-row']").find { |item| item.text.include?(loan.name) }
    assert_not_nil debt_row
    assert_includes debt_row.text, "Deuda en Yogasto"
    assert_includes debt_row.text, "Verificar saldo"
    assert_includes debt_row.text, "Movimientos"

    accounts_panel = css_select(".rec-panel").find { |panel| panel.text.include?("Saldos de tus cuentas") }
    debts_panel = css_select(".rec-panel").find { |panel| panel.text.include?("Obligaciones por verificar") }
    refute_includes accounts_panel.text, loan.name
    assert_includes debts_panel.text, loan.name
  end

  test "a verified source can be changed again in the same cycle" do
    sign_in @user

    post reconciliation_actual_balance_path(@account), params: { mark_ok: "true" }
    assert_equal "ok", ReconciliationSnapshot.find_by(user: @user, money_source: @account).resolution

    post reconciliation_actual_balance_path(@account),
         params: { actual_balance: "8.500.000", adjust: "true", note: "Corrección" }

    assert_equal 8_500_000.to_d, @account.reload.balance
    assert_equal "ok", ReconciliationSnapshot.find_by(user: @user, money_source: @account).resolution
    assert_equal 1, ReconciliationSnapshot.for_period(@user, Date.current.strftime("%Y-%m")).count
  end
end
