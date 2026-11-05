# frozen_string_literal: true

require "test_helper"

class IncomesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Incomes Ctrl User",
      email: "incomes_ctrl_test@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "GET /incomes/new offers only payment sources in the source dropdown" do
    account = @user.money_sources.create!(name: "Cuenta Nómina", kind: "account")
    loan = @user.money_sources.create!(name: "Crédito Libre Inversión", kind: "loan", sub_kind: "personal")

    get new_income_path
    assert_response :success

    assert_select "select[name='income[money_source_id]'] option", text: /Cuenta Nómina/, count: 1
    assert_select "select[name='income[money_source_id]'] option", text: /Crédito Libre Inversión/, count: 0
    refute_includes response.body, loan.reload.name
    assert account.persisted?
  end

  test "GET /incomes/new offers only income categories" do
    income = Category.create!(name: "Salario", user: @user, is_default: false, category_type: "income")
    expense = Category.create!(name: "Mercado", user: @user, is_default: false, category_type: "expense")

    get new_income_path

    assert_response :success
    assert_select "[data-testid=income-category-picker] [role=option][data-value=?]", income.id.to_s
    assert_select "[data-testid=income-category-picker] [role=option][data-value=?]", expense.id.to_s, count: 0
  end

  test "GET /incomes/new renders the form inside a card with header and footer" do
    get new_income_path

    assert_response :success
    assert_select "form[action='#{incomes_path}'] .card" do
      assert_select ".card-header .icon-chip i.ti-cash-banknote"
      assert_select ".card-header h4", text: "Nuevo ingreso"
      assert_select ".card-header .card-subtitle", text: /Registra el dinero que entra/
      assert_select ".card-body input[name='income[amount]']"
      assert_select ".card-body input[name='income[description]']"
      assert_select ".card-body input[name='income[date]']"
      assert_select ".card-body select[name='income[money_source_id]']"
      assert_select ".card-footer a.btn.btn-outline-secondary[href=?]", incomes_path, text: "Cancelar"
      assert_select ".card-footer input[type=submit].btn.btn-primary"
    end
  end

  test "GET /incomes/:id/edit renders the form inside a card with header and footer" do
    income = @user.incomes.create!(
      amount: 1_500_000, description: "Salario", date: Date.current,
      category: Category.create!(name: "Salario edición", user: @user, is_default: false, category_type: "income"),
      money_source: @user.money_sources.create!(name: "Cuenta edición", kind: "account")
    )

    get edit_income_path(income)

    assert_response :success
    assert_select "form[action='#{income_path(income)}'] .card" do
      assert_select ".card-header h4", text: "Editar ingreso"
      assert_select ".card-header .card-subtitle", text: /Registra el dinero que entra/
      assert_select ".card-footer a.btn.btn-outline-secondary[href=?]", incomes_path, text: "Cancelar"
      assert_select ".card-footer input[type=submit].btn.btn-primary"
    end
  end

  test "GET /incomes shows the financial cycle badge in the title with a schedule" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.current(@user)

    get incomes_path

    assert_response :success
    assert_select "[data-testid=cycle-badge]", text: /#{cycle.label}/
    assert_select "[data-testid=cycle-badge]", text: /#{cycle.range_label}/
  end

  test "GET /incomes hides the cycle badge without a configured schedule" do
    get incomes_path

    assert_response :success
    assert_select "[data-testid=cycle-badge]", count: 0
  end

  test "GET /incomes/new defaults the date to today even with a cycle schedule" do
    @user.update!(financial_cycle_start_day: 20)

    get new_income_path

    assert_response :success
    assert_select "input[name='income[date]'][value=?]", Date.current.to_s
  end

  test "POST /incomes rejects a money source owned by another user" do
    other_user = User.create!(name: "Other", email: "create_income_foreign_source@example.com", password: "password123")
    foreign_source = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account", starting_balance: 500_000)
    category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    balance_before = foreign_source.reload.cached_balance

    assert_no_difference "Income.count" do
      post incomes_path, params: { income: {
        amount: 100_000, description: "Ingreso cruzado", date: Date.current.to_s,
        category_id: category.id, money_source_id: foreign_source.id
      } }
    end

    assert_response :unprocessable_entity
    assert_equal balance_before, foreign_source.reload.cached_balance
  end

  test "GET /incomes summarizes the selected financial cycle with real income data" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.current(@user)
    category = income_category("Salario resumen")
    source = @user.money_sources.create!(name: "Cuenta resumen", kind: "account")
    @user.incomes.create!(amount: 1_000_000, description: "Salario", date: cycle.starts,
                          category: category, money_source: source)
    @user.incomes.create!(amount: 500_000, description: "Bonificación", date: cycle.ends,
                          category: category, money_source: source)
    @user.incomes.create!(amount: 9_000_000, description: "Ingreso anterior", date: cycle.starts - 1.day,
                          category: category, money_source: source)
    @user.recurring_templates.create!(kind: "income", category: category, amount: 2_000_000,
                                      payment_day: 1, active: true)
    @user.recurring_templates.create!(kind: "expense", category: income_category("Gasto resumen"), amount: 800_000,
                                      payment_day: 5, active: true)

    get incomes_path

    assert_response :success
    assert_select "[data-testid=incomes-summary]"
    summary_total = css_select("[data-testid=summary-total]").first.text
    assert_includes summary_total, "1.500.000"
    refute_includes summary_total, "9.000.000"
    assert_select "[data-testid=summary-count]", text: "2"
    assert_select "[data-testid=summary-monthly]", text: "1"
  end

  test "GET /incomes summarizes the calendar month when no cycle is configured" do
    @user.update!(financial_cycle_start_day: 1)
    category = income_category("Salario mes")
    source = @user.money_sources.create!(name: "Cuenta mes", kind: "account")
    @user.incomes.create!(amount: 700_000, description: "Salario del mes", date: Date.current,
                          category: category, money_source: source)
    @user.incomes.create!(amount: 300_000, description: "Salario anterior", date: Date.current.prev_month,
                          category: category, money_source: source)

    get incomes_path

    assert_response :success
    summary_total = css_select("[data-testid=summary-total]").first.text
    assert_includes summary_total, "700.000"
    refute_includes summary_total, "1.000.000"
    assert_select "[data-testid=summary-count]", text: "1"
  end

  test "GET /incomes shows date, category, description, money source, amount and actions" do
    category = income_category("Salario tabla")
    source = @user.money_sources.create!(name: "Cuenta principal", kind: "account")
    income = @user.incomes.create!(amount: 1_500_000, description: "Pago mensual", date: Date.current,
                                   category: category, money_source: source)

    get incomes_path

    assert_response :success
    assert_select "table thead th", text: "Fecha"
    assert_select "table thead th", text: "Categoría"
    assert_select "table thead th", text: "Descripción"
    assert_select "table thead th", text: "Medio de dinero"
    assert_select "table thead th", text: "Monto"
    assert_select "table thead th", text: "Acciones"
    assert_select "[data-testid=row][data-id='#{income.id}']" do
      assert_select "td", text: /Pago mensual/
      assert_select "[data-testid=money-source]", text: /Cuenta principal/
      assert_select "a[href='#{edit_income_path(income)}']"
      assert_select "form[action='#{income_path(income)}'] button"
    end
  end

  test "GET /incomes eager loads credit card details for money source labels" do
    category = income_category("Salario tarjetas")
    card_one = @user.money_sources.create!(name: "Visa", kind: "credit_card")
    card_one.create_credit_account!(credit_limit: 2_000_000, card_last_four: "1234")
    card_two = @user.money_sources.create!(name: "Mastercard", kind: "credit_card")
    card_two.create_credit_account!(credit_limit: 3_000_000, card_last_four: "5678")
    @user.incomes.create!(amount: 1_000_000, description: "Pago Visa", date: Date.current,
                          category: category, money_source: card_one)
    @user.incomes.create!(amount: 500_000, description: "Pago Mastercard", date: Date.current,
                          category: category, money_source: card_two)

    Bullet.enable = true
    Bullet.raise = true

    get incomes_path

    assert_response :success
    assert_select "[data-testid=money-source]", text: /1234/
    assert_select "[data-testid=money-source]", text: /5678/
  ensure
    Bullet.enable = false
    Bullet.raise = false
  end

  test "GET /incomes filters recent incomes by description and category" do
    salary_category = income_category("Salario filtro")
    freelance_category = income_category("Honorarios filtro")
    source = @user.money_sources.create!(name: "Cuenta filtros", kind: "account")
    salary = @user.incomes.create!(amount: 1_000_000, description: "Pago mensual", date: Date.current,
                                   category: salary_category, money_source: source)
    freelance = @user.incomes.create!(amount: 500_000, description: "Proyecto freelance", date: Date.current,
                                      category: freelance_category, money_source: source)

    get incomes_path(q: "mensual")

    assert_response :success
    assert_select "[data-testid=row][data-id='#{salary.id}']"
    assert_select "[data-testid=row][data-id='#{freelance.id}']", count: 0

    get incomes_path(category_id: freelance_category.id)

    assert_response :success
    assert_select "[data-testid=row][data-id='#{freelance.id}']"
    assert_select "[data-testid=row][data-id='#{salary.id}']", count: 0
  end

  test "GET /incomes shows a filtered empty state without matching incomes" do
    category = income_category("Salario vacío")
    source = @user.money_sources.create!(name: "Cuenta vacía", kind: "account")
    @user.incomes.create!(amount: 900_000, description: "Pago mensual", date: Date.current,
                          category: category, money_source: source)

    get incomes_path(q: "no-existe")

    assert_response :success
    assert_select "[data-testid=filtered-empty]", text: /No encontramos ingresos/
    assert_select "[data-testid=row]", count: 0
  end

  private

  def income_category(name)
    Category.create!(name: name, user: @user, is_default: false, category_type: "income")
  end
end
