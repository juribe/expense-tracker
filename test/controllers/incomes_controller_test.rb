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
end
