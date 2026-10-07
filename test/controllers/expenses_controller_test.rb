# frozen_string_literal: true

require "test_helper"

class ExpensesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "expenses_index_test@example.com",
      password: "password123"
    )
    @category = Category.create!(name: "Food", is_default: true, category_type: "expense")
    @other_category = Category.create!(name: "Transport", is_default: true, category_type: "expense")
    sign_in @user
    @template = @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: 65_000, frequency: "monthly",
      source: "wizard", description: "Cuota Vehículo"
    )
  end

  def create_expense(amount:, date:, category: @category, description: "Lunch", **extra)
    @user.expenses.create!({ amount: amount, date: date, category: category,
                             description: description }.merge(extra))
  end

  def template_for(amount:, active: true)
    @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: amount, frequency: "monthly",
      source: "wizard", description: "Cuota Vehículo", active: active
    )
  end

  test "GET /expenses renders the table with expenses" do
    source = create_source(name: "Visa", kind: "credit_card", bank: "Chase")
    create_expense(amount: 12.50, date: Date.today, money_source: source)
    get expenses_path
    assert_response :success
    assert_select "[data-testid=table]"
    assert_select "tr[data-testid=row]", count: 1
    assert_select "tr[data-testid=row] td .badge", text: /Visa/
    assert_select "tr[data-testid=row] td .bi-credit-card-2-front"
    assert_select "form[data-testid=filter-form]"
    assert_select "#resultsMeta", text: /1 gasto/
  end

  test "GET /expenses/:id shows the money source with its icon" do
    source = create_source(name: "Nequi", kind: "wallet", bank: "Bancolombia")
    expense = create_expense(amount: 20.00, date: Date.today, money_source: source)
    get expense_path(expense)
    assert_response :success
    assert_select "dd .badge", text: /Nequi/
    assert_select "dd .bi-wallet2"
  end

  test "GET /expenses renders the bulk update bar and modal" do
    create_expense(amount: 12.50, date: Date.today)
    create_source(name: "Visa", kind: "credit_card", bank: "Chase")
    get expenses_path
    assert_response :success
    assert_select "#bulkBar button[data-testid=bulk-category]"
    assert_select "#bulkBar button[data-testid=bulk-source]"
    assert_select "#bulkEditModal[data-testid=bulk-update-modal]"
    assert_select "select#bulkCategorySelect option", text: "Food"
    assert_select "[data-testid=bulk-category-picker] [role=combobox]"
    assert_select "[data-testid=bulk-category-picker] [role=option]", text: "Food"
    assert_select "select[data-testid=bulk-source-select] option", text: "Visa · Chase"
    assert_select "button[data-testid=confirm-bulk-update]"
  end

  test "GET /expenses shows empty state when no expenses exist" do
    get expenses_path
    assert_response :success
    assert_select "[data-testid=empty]"
    assert_select "h2", text: I18n.t("expenses.empty_title")
    assert_select "table", count: 0
  end

  test "GET /expenses shows no-results state when filters match nothing" do
    create_expense(amount: 12.50, date: Date.today)
    get expenses_path, params: { category_id: @other_category.id }
    assert_response :success
    assert_select "[data-testid=empty]"
    assert_select "h2", text: I18n.t("expenses.no_results_title")
  end

  test "GET /expenses filters by category with a row-level where filter" do
    create_expense(amount: 12.50, date: Date.today, category: @category)
    create_expense(amount: 9.00, date: Date.today, category: @other_category, description: "Bus")
    get expenses_path, params: { category_id: @category.id }
    assert_response :success
    assert_select "tr[data-testid=row]", count: 1
    assert_select "td", text: "Lunch"
    assert_no_match(/Bus/, response.body)
  end

  test "GET /expenses filters by amount range" do
    create_expense(amount: 10.00, date: Date.today, description: "Low")
    create_expense(amount: 50.00, date: Date.today, description: "Mid")
    create_expense(amount: 100.00, date: Date.today, description: "High")
    get expenses_path, params: { min_amount: "20", max_amount: "75" }
    assert_response :success
    assert_select "tr[data-testid=row]", count: 1
    assert_select "td", text: "Mid"
  end

  test "GET /expenses filters by date range" do
    create_expense(amount: 10.00, date: Date.new(2026, 1, 10), description: "Old")
    create_expense(amount: 20.00, date: Date.new(2026, 3, 15), description: "Rent")
    get expenses_path, params: { start_date: "2026-03-01", end_date: "2026-03-31" }
    assert_response :success
    assert_select "tr[data-testid=row]", count: 1
    assert_select "td", text: "Rent"
  end

  test "GET /expenses validates min > max amount and does not run the query" do
    create_expense(amount: 50.00, date: Date.today)
    get expenses_path, params: { min_amount: "100", max_amount: "10" }
    assert_response :success
    assert_select "input.is-invalid"
    assert_select "tr[data-testid=row]", count: 0
  end

  test "GET /expenses validates start date after end date" do
    get expenses_path, params: { start_date: "2026-04-01", end_date: "2026-03-01" }
    assert_response :success
    assert_select "input.is-invalid"
    assert_select "div.alert-danger", text: /Corrige/
  end

  test "GET /expenses sorts by amount ascending" do
    create_expense(amount: 10.00, date: Date.today, description: "Low")
    create_expense(amount: 99.00, date: Date.today, description: "High")
    get expenses_path, params: { sort: "amount", dir: "asc" }
    assert_response :success
    assert_select "thead th[aria-sort=ascending]"
    body = response.body
    assert body.index("Low") < body.index("High"), "expected amount ascending order"
  end

  test "GET /expenses defaults to date descending sort" do
    create_expense(amount: 10.00, date: Date.new(2026, 1, 1), description: "Old")
    create_expense(amount: 20.00, date: Date.new(2026, 5, 1), description: "New")
    get expenses_path
    assert_response :success
    assert_select "thead th[aria-sort=descending]"
    body = response.body
    assert body.index("New") < body.index("Old"), "expected date descending order"
  end

  test "GET /expenses paginates at 25 rows and preserves page param" do
    30.times { |i| create_expense(amount: i + 1, date: Date.today, description: "Expense #{i}") }
    get expenses_path, params: { page: 1 }
    assert_response :success
    assert_select "tr[data-testid=row]", count: 25
    assert_select "nav[data-testid=pagination]"
    get expenses_path, params: { page: 2 }
    assert_select "tr[data-testid=row]", count: 5
  end

  test "GET /expenses shows the subtotal of the visible page, not the filtered total" do
    30.times { |i| create_expense(amount: 10.0 + i, date: Date.today, description: "Expense #{i}") }
    get expenses_path, params: { page: 2 }
    assert_response :success
    assert_select "#pageFoot", text: /Total de página -\$60/
    assert_select "#pageFoot", text: /Total filtrado -\$735/
  end

  test "GET /expenses.csv exports the filtered set as CSV" do
    create_expense(amount: 12.50, date: Date.new(2026, 3, 10), description: 'Lunch, "business"')
    create_expense(amount: 8.00, date: Date.new(2026, 1, 1), description: "Excluded", category: @other_category)
    get expenses_path(format: :csv), params: { category_id: @category.id }
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "date,description,category,amount"
    assert_includes response.body, '2026-03-10,"Lunch, ""business""",Food,-12.5'
    assert_includes response.body, "Food"
    refute_includes response.body, "Excluded"
  end

  test "GET /expenses/:id renders the drawer fragment" do
    expense = create_expense(amount: 12.50, date: Date.today)
    get expense_path(expense)
    assert_response :success
    assert_select "dl.drawer-dl"
    assert_select "dt", text: I18n.t("common.amount")
  end

  test "GET /expenses/:id drawer shows the recurring link badge and unlink button" do
    expense = create_expense(amount: 63_500, date: Date.today)
    expense.update!(recurring_template_id: @template.id)

    get expense_path(expense)
    assert_response :success
    assert_select "[data-testid=unlink-recurring]"
    assert_select "dd .badge", text: /Cuota Vehículo/
  end

  test "GET /expenses/:id drawer shows no recurring link for unlinked expenses" do
    expense = create_expense(amount: 12.50, date: Date.today)
    get expense_path(expense)
    assert_select "dd", text: /Sin asignar/
  end

  test "DELETE /expenses/:id destroys and preserves filter query" do
    expense = create_expense(amount: 12.50, date: Date.today)
    delete expense_path(expense), params: { category_id: @category.id, sort: "amount", dir: "asc" }
    assert_redirected_to expenses_path(category_id: @category.id.to_s, sort: "amount", dir: "asc")
    assert_not Expense.exists?(expense.id)
    follow_redirect!
    assert_equal I18n.t("expenses.deleted"), flash[:notice]
  end

  test "DELETE /expenses/bulk_destroy removes selected expenses" do
    a = create_expense(amount: 1, date: Date.today, description: "A")
    b = create_expense(amount: 2, date: Date.today, description: "B")
    c = create_expense(amount: 3, date: Date.today, description: "C")
    delete bulk_destroy_expenses_path, params: { ids: [ a.id, c.id ] }
    assert_redirected_to expenses_path
    assert Expense.exists?(b.id)
    assert_not Expense.exists?(a.id)
    assert_not Expense.exists?(c.id)
  end

  test "DELETE /expenses/bulk_destroy with no ids redirects with alert" do
    delete bulk_destroy_expenses_path, params: { ids: [] }
    assert_redirected_to expenses_path
    follow_redirect!
    assert_equal I18n.t("expenses.no_selection"), flash[:alert]
  end

  def create_source(name: "Credit Card", kind: "credit_card", **opts)
    @user.money_sources.create!({ name: name, kind: kind, starting_balance: 0 }.merge(opts))
  end

  test "GET /expenses/new offers only payment sources in the source dropdown" do
    card = create_source(name: "Visa", kind: "credit_card")
    loan = create_source(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle")

    get new_expense_path
    assert_response :success

    assert_select "select[name='expense[money_source_id]'] option", text: /Visa/, count: 1
    assert_select "select[name='expense[money_source_id]'] option", text: /Crédito Vehículo/, count: 0
    refute_includes response.body, loan.reload.name
  end

  test "GET /expenses/new defaults the date to the current cycle start with a schedule" do
    @user.update!(financial_cycle_start_day: 20)
    expected = PayCycle.current(@user).starts

    get new_expense_path

    assert_response :success
    assert_select "input[name='expense[date]'][value=?]", expected.to_s
  end

  test "GET /expenses prefills the current cycle when no date filter is given" do
    @user.update!(financial_cycle_start_day: 20)
    # Inside the cycle opened this month (dated at its start).
    @user.expenses.create!(amount: -500_000, date: PayCycle.current(@user).starts,
                           category: @category, description: "Arriendo en ciclo")
    # Outside it (belongs to the next cycle).
    @user.expenses.create!(amount: -900_000, date: PayCycle.current(@user).ends + 5, category: @category,
                           description: "Fuera de ciclo")

    get expenses_path

    assert_response :success
    assert_select '[data-testid="cycle-badge"]'
    assert_includes response.body, "Arriendo en ciclo"
    refute_includes response.body, "Fuera de ciclo"
  end

  test "GET /expenses skips the cycle prefill when explicit dates are given" do
    @user.update!(financial_cycle_start_day: 20)

    get expenses_path, params: { start_date: Date.current.iso8601, end_date: Date.current.iso8601 }

    assert_response :success
    assert_select '[data-testid="cycle-badge"]', count: 0
  end

  test "GET /expenses/:id/edit offers only payment sources in the source dropdown" do
    expense = create_expense(amount: 10, date: Date.today)
    card = create_source(name: "Visa", kind: "credit_card")
    loan = create_source(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle")

    get edit_expense_path(expense)
    assert_response :success

    assert_select "select[name='expense[money_source_id]'] option", text: /Visa/, count: 1
    assert_select "select[name='expense[money_source_id]'] option", text: /Crédito Vehículo/, count: 0
  end

  # ------------------------------------------------ apply to recurring

  test "POST /expenses/assign_recurring assigns an expense to an expense template" do
    expense = create_expense(amount: 63_500, date: Date.today, description: "Cuota Veículo", source: "gmail")
    template = template_for(amount: 65_000)

    post assign_recurring_expenses_path, params: { expense_id: expense.id, recurring_template_id: template.id }

    assert_redirected_to expenses_path
    assert_equal template.id, expense.reload.recurring_template_id
    assert_equal :completed, template.status_for(Date.current.strftime("%Y-%m"))
    assert_equal expense.id, template.last_occurrence.id
    follow_redirect!
    assert_equal I18n.t("expenses.assign_recurring.applied", description: template.description), flash[:notice]
  end

  test "POST /expenses/assign_recurring rejects when the template already paid that period" do
    expense = create_expense(amount: 50_000, date: Date.today)
    template = template_for(amount: 50_000)
    template.transactions.create!(user: @user, category: @category, amount: 50_000,
                                  date: Date.today, kind: "expense", source: "recurring_template")

    post assign_recurring_expenses_path, params: { expense_id: expense.id, recurring_template_id: template.id }

    assert_redirected_to expenses_path
    assert_nil expense.reload.recurring_template_id
    assert_equal I18n.t("expenses.assign_recurring.period_taken", description: template.description), flash[:alert]
  end

  test "POST /expenses/assign_recurring rejects an already linked expense" do
    expense = create_expense(amount: 50_000, date: Date.today)
    first = template_for(amount: 50_000)
    expense.update!(recurring_template_id: first.id)
    second = template_for(amount: 50_000)

    post assign_recurring_expenses_path, params: { expense_id: expense.id, recurring_template_id: second.id }

    assert_redirected_to expenses_path
    assert_equal first.id, expense.reload.recurring_template_id
    assert_equal I18n.t("expenses.assign_recurring.already_linked"), flash[:alert]
  end

  test "POST /expenses/assign_recurring rejects an income template" do
    expense = create_expense(amount: 50_000, date: Date.today)
    income_template = @user.recurring_templates.create!(
      category: @category, kind: "income", amount: 3_000_000, frequency: "monthly", source: "manual"
    )

    post assign_recurring_expenses_path, params: { expense_id: expense.id, recurring_template_id: income_template.id }

    assert_redirected_to expenses_path
    assert_nil expense.reload.recurring_template_id
    assert_equal I18n.t("expenses.assign_recurring.not_expense"), flash[:alert]
  end

  test "POST /expenses/assign_recurring rejects a debt-target template" do
    expense = create_expense(amount: 50_000, date: Date.today)
    loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    debt_template = @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: 3_000_000, frequency: "monthly",
      source: "manual", money_source: loan
    )

    post assign_recurring_expenses_path, params: { expense_id: expense.id, recurring_template_id: debt_template.id }

    assert_redirected_to expenses_path
    assert_nil expense.reload.recurring_template_id
    assert_equal I18n.t("expenses.assign_recurring.debt_target"), flash[:alert]
  end

  test "bulk assign modal template list excludes debt-target templates" do
    loan = MoneySource.create!(user: @user, name: "Crédito carro", kind: "loan")
    @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: 3_000_000, frequency: "monthly",
      source: "manual", money_source: loan
    )

    get expenses_path

    assert_response :success
    assert_not @controller.view_assigns["recurring_templates"].any? { |t| t.money_source&.debt_payment_target? }
  end

  test "POST /expenses/assign_recurring rejects an inactive template" do
    expense = create_expense(amount: 50_000, date: Date.today)
    template = template_for(amount: 50_000, active: false)

    post assign_recurring_expenses_path, params: { expense_id: expense.id, recurring_template_id: template.id }

    assert_redirected_to expenses_path
    assert_nil expense.reload.recurring_template_id
    assert_equal I18n.t("expenses.assign_recurring.inactive"), flash[:alert]
  end

  test "POST /expenses/assign_recurring rejects other users' expense and template" do
    other = User.create!(name: "Other", email: "other_assign_recurring@example.com", password: "password123")
    other_expense = other.expenses.create!(category: @category, amount: 50_000, date: Date.today, source: "gmail")
    other_template = other.recurring_templates.create!(
      category: @category, kind: "expense", amount: 50_000, frequency: "monthly", source: "wizard"
    )

    post assign_recurring_expenses_path, params: { expense_id: other_expense.id, recurring_template_id: @template.id }
    assert_equal I18n.t("expenses.assign_recurring.not_found"), flash[:alert]

    post assign_recurring_expenses_path, params: { expense_id: create_expense(amount: 1, date: Date.today).id,
                                                  recurring_template_id: other_template.id }
    assert_equal I18n.t("expenses.assign_recurring.not_found"), flash[:alert]
  end

  test "POST /expenses/unassign_recurring clears the link and reopens the period" do
    expense = create_expense(amount: 50_000, date: Date.today)
    template = template_for(amount: 50_000)
    expense.update!(recurring_template_id: template.id)
    assert_equal :completed, template.status_for(Date.current.strftime("%Y-%m"))

    post unassign_recurring_expenses_path, params: { expense_id: expense.id }

    assert_redirected_to expenses_path
    assert_nil expense.reload.recurring_template_id
    assert_equal :pending, template.status_for(Date.current.strftime("%Y-%m"))
  end

  test "POST /expenses/unassign_recurring rejects an unlinked or foreign expense" do
    expense = create_expense(amount: 50_000, date: Date.today)
    post unassign_recurring_expenses_path, params: { expense_id: expense.id }
    assert_equal I18n.t("expenses.assign_recurring.not_linked"), flash[:alert]

    other = User.create!(name: "Other2", email: "other2_assign_recurring@example.com", password: "password123")
    other_expense = other.expenses.create!(category: @category, amount: 1, date: Date.today, source: "gmail")
    other_expense.update!(recurring_template_id: template_for(amount: 1).id)
    post unassign_recurring_expenses_path, params: { expense_id: other_expense.id }
    assert_equal I18n.t("expenses.assign_recurring.not_linked"), flash[:alert]
    assert other_expense.reload.recurring_template_id.present?
  end

  test "GET /expenses shows the per-row apply-to-recurring button and template options" do
    create_expense(amount: 63_500, date: Date.today, source: "gmail")

    get expenses_path
    assert_response :success

    # Per-row button (not bulk-bar), only for unlinked expenses.
    assert_select "[data-testid=bulk-recurring]", count: 0
    assert_select "tr[data-testid=row][data-recurring-id=''] [data-testid=row-assign-recurring]", count: 1
    # Already-linked expenses don't offer the button again (2 rows, 1 linked).
    linked = create_expense(amount: 1, date: Date.today)
    linked.update!(recurring_template_id: @template.id)
    get expenses_path
    assert_select "[data-testid=row-assign-recurring]", count: 1
    assert_select "select option", text: /Cuota Vehículo/
  end

  test "assigning to a credit-card template is rejected: apply the payment from the account page" do
    source = create_source(name: "Visa", kind: "credit_card", bank: "Chase")
    source.create_credit_account!(credit_limit: 3_000_000)
    expense = create_expense(amount: 1_500_000, date: Date.today, source: "gmail", money_source: source)
    template = template_for(amount: 1_500_000)
    template.update!(money_source: source, description: "Cuota Visa")
    card_balance_before = source.reload.balance

    post assign_recurring_expenses_path, params: { expense_id: expense.id, recurring_template_id: template.id }

    assert_redirected_to expenses_path
    assert_equal I18n.t("expenses.assign_recurring.debt_target"), flash[:alert]
    assert_not Payment.exists?
    assert_nil expense.reload.recurring_template_id
    assert_equal card_balance_before, source.reload.balance
    assert_equal 0, source.credit_account.installments_paid.to_i
  end

  test "GET /expenses renders templates already paid this period as unavailable options" do
    create_expense(amount: 1, date: Date.today, source: "gmail")
    template = template_for(amount: 20_000, active: true)
    expense = create_expense(amount: 20_000, date: Date.today)
    expense.update!(recurring_template_id: template.id)

    get expenses_path
    assert_response :success
    assert_select "select#bulkRecurringSelect option[disabled]", text: /Pagado/
  end

  test "GET /expenses rows keep the eye-only drawer button" do
    create_expense(amount: 10, date: Date.today)
    get expenses_path
    assert_response :success
    assert_select "tr[data-testid=row] [data-open-drawer]", count: 1
  end

  test "PATCH /expenses/bulk_update changes category for selected expenses" do
    a = create_expense(amount: 1, date: Date.today, description: "A")
    b = create_expense(amount: 2, date: Date.today, description: "B")
    patch bulk_update_expenses_path, params: { expense_ids: [ a.id, b.id ], category_id: @other_category.id }
    assert_redirected_to expenses_path
    assert_equal @other_category.id, a.reload.category_id
    assert_equal @other_category.id, b.reload.category_id
    follow_redirect!
    assert_equal I18n.t("expenses.bulk_updated", count: 2), flash[:notice]
  end

  test "PATCH /expenses/bulk_update changes money source for selected expenses" do
    a = create_expense(amount: 1, date: Date.today)
    b = create_expense(amount: 2, date: Date.today)
    source = create_source
    patch bulk_update_expenses_path, params: { expense_ids: [ a.id, b.id ], money_source_id: source.id }
    assert_redirected_to expenses_path
    assert_equal source.id, a.reload.money_source_id
    assert_equal source.id, b.reload.money_source_id
  end

  test "PATCH /expenses/bulk_update changes category and money source in one request" do
    a = create_expense(amount: 1, date: Date.today)
    source = create_source
    patch bulk_update_expenses_path,
          params: { expense_ids: [ a.id ], category_id: @other_category.id, money_source_id: source.id }
    assert_redirected_to expenses_path
    a.reload
    assert_equal @other_category.id, a.category_id
    assert_equal source.id, a.money_source_id
  end

  test "PATCH /expenses/bulk_update only updates the fields provided" do
    source = create_source
    a = create_expense(amount: 1, date: Date.today)
    a.update!(money_source_id: source.id)
    patch bulk_update_expenses_path, params: { expense_ids: [ a.id ], category_id: @other_category.id }
    assert_redirected_to expenses_path
    a.reload
    assert_equal @other_category.id, a.category_id
    assert_equal source.id, a.money_source_id
  end

  test "PATCH /expenses/bulk_update ignores expense ids not owned by the current user" do
    other_user = User.create!(name: "Other", email: "bulk_update_other@example.com", password: "password123")
    other_expense = other_user.expenses.create!(amount: 5, date: Date.today, description: "Theirs", category: @category)
    mine = create_expense(amount: 2, date: Date.today)
    patch bulk_update_expenses_path, params: { expense_ids: [ mine.id, other_expense.id ], category_id: @other_category.id }
    assert_redirected_to expenses_path
    assert_equal @other_category.id, mine.reload.category_id
    assert_not_equal @other_category.id, other_expense.reload.category_id
    follow_redirect!
    assert_equal I18n.t("expenses.bulk_updated", count: 1), flash[:notice]
  end

  test "PATCH /expenses/bulk_update rejects a category not available to the user" do
    other_user = User.create!(name: "Other", email: "bulk_update_cat_other@example.com", password: "password123")
    other_category = Category.create!(name: "Secret Cat", user: other_user, is_default: false, category_type: "expense")
    a = create_expense(amount: 1, date: Date.today)
    original = a.category_id
    patch bulk_update_expenses_path, params: { expense_ids: [ a.id ], category_id: other_category.id }
    assert_redirected_to expenses_path
    assert_equal original, a.reload.category_id
    follow_redirect!
    assert_equal I18n.t("expenses.update_category_not_found"), flash[:alert]
  end

  test "PATCH /expenses/bulk_update rejects a money source not owned by the user" do
    other_user = User.create!(name: "Other", email: "bulk_update_src_other@example.com", password: "password123")
    other_source = other_user.money_sources.create!(name: "Other Bank", kind: "account", starting_balance: 0)
    a = create_expense(amount: 1, date: Date.today)
    patch bulk_update_expenses_path, params: { expense_ids: [ a.id ], money_source_id: other_source.id }
    assert_redirected_to expenses_path
    assert_nil a.reload.money_source_id
    follow_redirect!
    assert_equal I18n.t("expenses.update_source_not_found"), flash[:alert]
  end

  test "PATCH /expenses/bulk_update rejects empty expense ids" do
    patch bulk_update_expenses_path, params: { expense_ids: [], category_id: @other_category.id }
    assert_redirected_to expenses_path
    follow_redirect!
    assert_equal I18n.t("expenses.no_selection"), flash[:alert]
  end

  test "PATCH /expenses/bulk_update rejects requests without any field to change" do
    a = create_expense(amount: 1, date: Date.today)
    patch bulk_update_expenses_path, params: { expense_ids: [ a.id ] }
    assert_redirected_to expenses_path
    follow_redirect!
    assert_equal I18n.t("expenses.choose_category_or_source"), flash[:alert]
  end

  test "PATCH /expenses/bulk_update preserves filters, sort, and page on redirect" do
    a = create_expense(amount: 1, date: Date.today)
    url = bulk_update_expenses_path(category_id: @category.id, sort: "date", dir: "asc", page: "2")
    patch url, params: { expense_ids: [ a.id ], category_id: @other_category.id }
    assert_redirected_to expenses_path(category_id: @category.id.to_s, sort: "date", dir: "asc", page: "2")
  end

  test "GET /expenses does not trigger an N+1 on money sources or credit accounts" do
    create_expense(amount: 1, date: Date.today)
    cards = 3.times.map do |i|
      card = create_source(name: "Tarjeta #{i}", kind: "credit_card")
      card.build_credit_account(credit_limit: 1000, card_brand: "visa", card_last_four: "123#{i}").save!
      create_expense(amount: 10 + i, date: Date.today, money_source: card)
      card
    end

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].to_s =~ /FROM "(money_sources|credit_accounts)"/i }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get expenses_path
    end

    assert_response :ok
    {
      "money_sources" => /FROM "money_sources" WHERE "money_sources"\."id" = /,
      "credit_accounts" => /FROM "credit_accounts" WHERE "credit_accounts"\."money_source_id" = /
    }.each do |table, n1_pattern|
      count = queries.grep(n1_pattern).length
      assert_operator count, :<=, 1,
        "expected at most one #{table} query, got #{count}: #{queries.join(' | ')}"
    end
  end
end
