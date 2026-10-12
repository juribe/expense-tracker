# frozen_string_literal: true

require "test_helper"

class DebtCapacityControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Debt Capacity User",
      email: "debt_capacity_controller_test@example.com",
      password: "password123"
    )
    @income_category = Category.create!(name: "Salario", category_type: "income", is_default: true)
    @user.recurring_templates.create!(category: @income_category, amount: 10_000_000, kind: "income",
                                      frequency: "monthly", source: "manual", active: true)
  end

  test "GET /debt_capacity renders the debt capacity page for an authenticated user" do
    sign_in @user

    get debt_capacity_path

    assert_response :success
    assert_select "h1", text: /Deudas y capacidad de endeudamiento/
    assert_select "[data-testid=debt-capacity-page]"
    assert_select "[data-testid=debt-capacity-summary]"
    assert_select "[data-testid=debt-capacity-current]", text: /Estás aquí: 0,0%/
    assert_select "[data-testid=debt-capacity-cash-flow]", text: /Gastos esenciales/
    assert_select "[data-testid=debt-capacity-cash-flow] strong.amt-debt", count: 2
    assert_select "[data-testid=debt-capacity-table]"
    assert_select "[data-testid=debt-capacity-table-totals]", text: /Total/
    assert_select "[data-testid=debt-capacity-recommendations]"
    assert_select "[data-testid=debt-capacity-comparison]"
    assert_select ".filters-card", count: 0
  end

  test "GET /debt_capacity redirects an unauthenticated user to sign in" do
    get debt_capacity_path

    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "GET /debt_capacity accepts a table sort parameter" do
    sign_in @user

    get debt_capacity_path(sort: "interest_rate", direction: "desc")

    assert_response :success
  end

  test "GET /debt_capacity/comparison renders the selected debt simulation" do
    source = @user.money_sources.create!(name: "Crédito personal", kind: "loan", active: true)
    source.create_credit_account!(outstanding_balance: 20_000_000, installment_amount: 1_130_642,
                                  interest_rate: 18.05, interest_rate_type: "effective_annual",
                                  payment_frequency: "monthly")
    sign_in @user

    get debt_capacity_comparison_path, params: { debt_id: source.id, amount: 5_000_000, mode: "reduce_term" }

    assert_response :success
    assert_select "[data-testid=debt-capacity-comparison]", text: /Crédito personal/
    assert_select "[data-testid=debt-capacity-comparison] th", text: "Deuda total", count: 0
    assert_select "[data-debt-comparison-form] input[data-money-input='true'][inputmode='decimal']"
    assert_select "[data-debt-comparison-form] [data-debt-comparison-installments-field].d-none"
    assert_select "[data-debt-comparison-form] input[name='mode'][value='reduce_term'][checked]"
  end

  test "GET /debt_capacity/comparison shows the installment count for a revolving credit" do
    source = @user.money_sources.create!(name: "Crédito rotativo", kind: "loan", sub_kind: "revolving", active: true)
    source.create_credit_account!(outstanding_balance: 20_000_000, installment_amount: 1_130_642,
                                  installment_count: 48, interest_rate: 18.05,
                                  interest_rate_type: "effective_annual", payment_frequency: "monthly")
    sign_in @user

    get debt_capacity_comparison_path,
        params: { debt_id: source.id, amount: 5_000_000, mode: "reduce_installment", installment_count: 36 }

    assert_response :success
    assert_select "[data-debt-comparison-form] input[data-debt-comparison-installments][value='36']"
    assert_select "[data-debt-comparison-form] label[for='installment_count']", text: "Saldo en cuotas estimadas"
    assert_select "[data-debt-comparison-form] .form-text", count: 0
    assert_select "[data-debt-comparison-form] [data-debt-comparison-term-option].d-none input[name='mode'][value='reduce_term']"
    assert_select "[data-debt-comparison-form] input[name='mode'][value='reduce_installment'][checked]"
  end
end
