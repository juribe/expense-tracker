# frozen_string_literal: true

require "test_helper"

# PaymentsController: manual "aplicar pago" of an existing Expense onto a
# debt (credit card or loan). The Debt is always a money_source nested path.
class PaymentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::Helpers::NumberHelper

  setup do
    @user = User.create!(name: "Test User", email: "payments_ctrl@example.com", password: "password123")
    sign_in @user
    @account = create_source(kind: "account", name: "Cuenta Davibank")
    @mortgage = create_source(kind: "loan", sub_kind: "mortgage", name: "Hipotecario", outstanding: 30_000_000)
    @card = create_source(kind: "credit_card", name: "Tarjeta", starting_balance: -500_000)
    @savings = create_source(kind: "account", name: "Ahorros")
  end

  # ------------------------------------------------------------- new
  test "GET new renders the manual distribution form with the expense amount as total" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    get new_money_source_payment_path(@mortgage, expense_id: expense.id)

    assert_response :success
    assert_match "payment", @response.body
  end

  test "GET new rejects an expense from another user" do
    other = User.create!(name: "Otro", email: "foreign-payments@example.com", password: "password123")
    foreign_expense = Expense.create!(
      user: other, amount: 500_000, description: "Ajeno",
      date: Date.current, kind: "expense", source: "manual", money_source_id: nil
    )

    get new_money_source_payment_path(@mortgage, expense_id: foreign_expense.id)

    assert_redirected_to money_source_path(@mortgage)
    assert_equal I18n.t("payments.not_found"), flash[:alert]
  end

  # ---------------------------------------------------------- create
  test "POST create applies the existing expense with a manual distribution and does NOT create another expense" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    assert_difference -> { Payment.count }, 1 do
      post money_source_payments_path(@mortgage), params: {
        expense_id: expense.id,
        payment: { principal_amount: "900.000", interest_amount: "400.000", other_amount: "200.000" }
      }
    end

    assert_redirected_to money_source_path(@mortgage)
    assert_equal 1, Expense.count
    payment = Payment.last
    assert_equal expense.id, payment.expense_id
    assert_equal BigDecimal("900000"), payment.principal_amount
    assert_equal BigDecimal("400000"), payment.interest_amount
    assert_equal BigDecimal("0"), payment.insurance_amount
    assert_equal BigDecimal("200000"), payment.other_amount
  end

  test "POST create rejects a distribution that does not sum to the expense amount" do
    expense = create_expense(amount: 1_500_000, money_source: @account)

    post money_source_payments_path(@mortgage), params: {
      expense_id: expense.id,
      payment: { principal_amount: "1000000", interest_amount: "400000" }
    }

    assert_response :unprocessable_entity
    assert_not Payment.exists?(expense_id: expense.id)
  end

  test "POST create rejects applying the same expense twice to the same debt" do
    expense = create_expense(amount: 600_000, money_source: @account)
    create_payment(expense, @mortgage, principal: 600_000)

    post money_source_payments_path(@mortgage), params: {
      expense_id: expense.id,
      payment: { principal_amount: "600000" }
    }

    assert_response :unprocessable_entity
    assert_equal 1, Payment.where(expense_id: expense.id, money_source_id: @mortgage.id).count
  end

  test "POST create cannot target a plain account" do
    expense = create_expense(amount: 600_000, money_source: @account)

    post money_source_payments_path(@savings), params: {
      expense_id: expense.id,
      payment: { principal_amount: "600000" }
    }

    assert_response :unprocessable_entity
    assert_not Payment.exists?
  end

  # ---------------------------------------------------------- update
  test "PATCH update changes the distribution and keeps the balance consistent" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    payment = create_payment(expense, @mortgage, principal: 900_000)

    patch money_source_payment_path(@mortgage, payment), params: {
      payment: { principal_amount: "850000", interest_amount: "650000" }
    }

    assert_redirected_to money_source_path(@mortgage)
    payment.reload
    assert_equal BigDecimal("850000"), payment.principal_amount
  end

  # -------------------------------------------------------- destroy
  test "DELETE destroy reverses the payment and restores the loan balance" do
    expense = create_expense(amount: 1_500_000, money_source: @account)
    payment = create_payment(expense, @mortgage, principal: 900_000)

    assert_difference -> { Payment.count }, -1 do
      delete money_source_payment_path(@mortgage, payment)
    end

    assert_redirected_to money_source_path(@mortgage)
    assert_equal BigDecimal("30_000_000"), @mortgage.reload.credit_account.outstanding_balance.to_d
  end

  # ---------------------------------------------------------------- show page
  test "GET /money_sources/:id lists applied payments and awaiting expenses on a debt page" do
    expense = create_expense(amount: 1_500_000, description: "Mortgage payment", money_source: @account)
    applied = Payment.create!(
      user: @user, expense: expense, money_source: @mortgage, date: Date.current.ago(40.days),
      amount: 1_500_000, principal_amount: 900_000, interest_amount: 600_000
    )

    get money_source_path(@mortgage)

    assert_response :success
    assert_select "table td", text: /Mortgage payment/
    assert_select "td", text: number_to_currency(applied.principal_amount)

    pending_expense = create_expense(amount: 1_400_000, description: "Pendiente listado", money_source: @account)
    template = @user.recurring_templates.create!(
      category: Category.create!(name: "Vivienda", user: @user, is_default: false, category_type: "expense"),
      kind: "expense", amount: 1_400_000, description: "Hipoteca", money_source: @mortgage
    )
    pending_expense.update!(recurring_template_id: template.id)

    get money_source_path(@mortgage)
    assert_select ".list-group-item", text: /Pendiente/
    assert_select ".list-group-item a[href*='payments/new']"
    assert_select "select#pickExpense option", text: /Pendiente listado/
  end

  test "applied payments paginate at 25 rows: page 1 shows the most recent and page 2 the older ones" do
    30.times do |i|
      expense = create_expense(amount: 600_000, description: "Cuota #{i}",
                               money_source: @account)
      expense.update_columns(date: Date.current.ago((i + 1) * 31.days))
      Payment.create!(
        user: @user, expense: expense, money_source: @mortgage, date: expense.date,
        amount: 600_000, principal_amount: 600_000
      )
    end

    get money_source_path(@mortgage)
    assert_response :success
    assert_select "table.table tbody tr", count: 25
    # Sorted most recent first: the newest payment (Cuota 0) is on page 1,
    # the oldest (Cuota 29) is not.
    assert_select "table tbody tr", text: /Cuota 0/
    assert_select "table tbody tr", text: /Cuota 29/, count: 0
    assert_select "a", text: /Siguiente/

    get money_source_path(@mortgage), params: { payments_page: 2 }
    assert_select "table.table tbody tr", count: 5
    assert_select "table tbody tr", text: /Cuota 29/
    assert_select "table tbody tr", text: /Cuota 0/, count: 0
  end

  # -------------------------------------------- email end-to-end flow
  test "email expense flow: assign to template, apply payment, no duplicate expense" do
    template = @user.recurring_templates.create!(
      category: create_category, kind: "expense", amount: 1_500_000,
      description: "Mortgage payment", payment_day: 25, source: "manual",
      money_source: @mortgage
    )
    expense = create_expense(amount: 1_500_000, description: "Payment", money_source: @account)

    post assign_recurring_expenses_path, params: { expense_id: expense.id, recurring_template_id: template.id }
    assert_redirected_to expenses_path

    post money_source_payments_path(@mortgage), params: {
      expense_id: expense.id,
      payment: { principal_amount: "900000", interest_amount: "400000", insurance_amount: "150000", other_amount: "50000" }
    }
    assert_redirected_to money_source_path(@mortgage)

    assert_equal 1, Expense.count
    assert_equal 1, Payment.count
    assert_equal BigDecimal("29_100_000.00"), @mortgage.reload.credit_account.outstanding_balance.to_d
  end

  private

  def create_source(kind:, name:, sub_kind: nil, starting_balance: 100_000, outstanding: nil)
    source = @user.money_sources.create!(name: name, kind: kind, sub_kind: sub_kind, starting_balance: starting_balance)
    source.create_credit_account!(principal_amount: 50_000_000, outstanding_balance: outstanding) if outstanding
    source
  end

  def create_category
    Category.create!(name: "Vivienda #{rand(1_000)}", user: @user, category_type: "expense")
  end

  def create_expense(amount:, description: "Payment", money_source: nil)
    Expense.create!(
      user: @user, amount: amount, description: description,
      date: Date.current, kind: "expense", source: "manual", money_source: money_source
    )
  end

  def create_payment(expense, target, principal:)
    Payment.create!(
      user: @user, expense: expense, money_source: target, date: expense.date,
      amount: expense.amount.to_d.abs, principal_amount: principal,
      interest_amount: expense.amount.to_d.abs - principal
    )
  end
end
