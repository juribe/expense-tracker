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

  test "GET /incomes/new defaults the date to the current cycle start with a schedule" do
    @user.update!(financial_cycle_start_day: 20)
    expected = PayCycle.current(@user).starts

    get new_income_path

    assert_response :success
    assert_select "input[name='income[date]'][value=?]", expected.to_s
  end
end
