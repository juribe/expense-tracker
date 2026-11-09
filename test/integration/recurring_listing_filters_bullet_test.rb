# frozen_string_literal: true

require "test_helper"

# Filtering a recurring listing by status can empty the table even though the
# SQL scope still returned rows (the status is computed in Ruby). Bullet used
# to flag the :category eager load on those requests although no row rendered
# the category badge: eager loading only pays off once the final list is known.
class RecurringListingFiltersBulletTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Recurring Filters User",
      email: "recurring_filters_bullet_test@example.com",
      password: "password123"
    )
    sign_in @user

    @account = @user.money_sources.create!(name: "Cuenta Filtros", kind: "account")
    @paid_expense_category = Category.create!(name: "Servicios pagados", is_default: false,
                                              category_type: "expense", user: @user)
    @pending_expense_category = Category.create!(name: "Servicios pendientes", is_default: false,
                                                 category_type: "expense", user: @user)
    @paid_income_category = Category.create!(name: "Salario pagado", is_default: false,
                                             category_type: "income", user: @user)

    @paid_expense = create_template(@paid_expense_category, "expense", 50_000)
    pay_in_full(@paid_expense, 50_000)
    @pending_expense = create_template(@pending_expense_category, "expense", 30_000)
    @paid_income = create_template(@paid_income_category, "income", 900_000)
    pay_in_full(@paid_income, 900_000)
  end

  test "monthly expenses filtered to pending in a fully paid category" do
    get monthly_expenses_path(status: "pending", category_id: @paid_expense_category.id)

    assert_response :success
    assert_select "[data-testid='empty-state']"
  end

  test "monthly expenses summary does not preload categories the table never renders" do
    get monthly_expenses_path(sort: "status", dir: "asc", status: "pending",
                              category_id: "", query: "", commit: "Filtrar")

    assert_response :success
  end

  test "monthly incomes filtered to pending in a fully paid category" do
    get monthly_incomes_path(status: "pending", category_id: @paid_income_category.id)

    assert_response :success
    assert_select "[data-testid='empty-state']"
  end

  test "recurring templates filtered to pending when every template is paid" do
    pay_in_full(@pending_expense, 30_000)

    get recurring_templates_path(kind: "expense", status: "pending")

    assert_response :success
    assert_select "[data-testid='empty-state']"
  end

  private

  def create_template(category, kind, amount)
    @user.recurring_templates.create!(
      category: category,
      kind: kind,
      amount: amount,
      frequency: "monthly",
      source: "wizard",
      description: "Plantilla #{category.name}"
    )
  end

  def pay_in_full(template, amount)
    template.transactions.create!(
      user: @user,
      category: template.category,
      amount: amount,
      date: Date.current,
      kind: template.kind,
      source: "recurring_template",
      money_source: @account
    )
  end
end
