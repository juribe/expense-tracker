# frozen_string_literal: true

require "test_helper"

# MonthlyExpenses recorre el mismo flujo del modal "Pagar" a través de
# RecurringTemplateActions: la fuente de dinero elegida en el modal llega
# hasta la transacción creada; sin elección aplica la fuente de la plantilla.
class MonthlyExpensesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Monthly Expenses User",
      email: "monthly_expenses_test@example.com",
      password: "password123"
    )
    sign_in @user
    @category = Category.create!(name: "Servicios Monthly Exp", is_default: false,
                                 category_type: "expense", user: @user)
    @account = @user.money_sources.create!(name: "Cuenta Nómina", kind: "account")
    @loan = @user.money_sources.create!(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle")
    @template = @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: 42_000, frequency: "monthly",
      source: "wizard", description: "Cuota Vehículo", money_source: @loan
    )
  end

  test "GET /monthly_expenses renders the pay modal with payment sources only" do
    get monthly_expenses_path
    assert_response :success

    assert_select "#processModal #processMoneySource option" do |options|
      values = options.map { |o| o["value"] }
      assert_includes values, ""
      assert_includes values, @account.id.to_s
      assert_not_includes values, @loan.id.to_s
    end
  end

  test "POST process with the chosen source records the payment from there" do
    post process_transaction_monthly_expense_path(@template), params: {
      amount: "42000", date: Date.current.to_s, money_source_id: @account.id
    }

    assert_redirected_to monthly_expenses_path
    assert_equal @account.id, @template.transactions.last.money_source_id
  end

  test "POST process without an explicit source falls back to the template source" do
    post process_transaction_monthly_expense_path(@template), params: {
      amount: "42000", date: Date.current.to_s
    }

    assert_redirected_to monthly_expenses_path
    assert_equal @loan.id, @template.transactions.last.money_source_id
  end

  test "POST process rejects a money source that is not a payment source" do
    assert_no_difference "Transaction.count" do
      post process_transaction_monthly_expense_path(@template), params: {
        amount: "42000", date: Date.current.to_s, money_source_id: @loan.id
      }
    end
    assert_redirected_to monthly_expenses_path
    assert_equal I18n.t("recurring.invalid_payment_source"), flash[:alert]
  end
end
