# frozen_string_literal: true

require "test_helper"

class ReportsSavingsCapacityControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Savings Capacity Page", email: "savings_capacity_page@example.com",
                         password: "password123")
    @user.update!(financial_cycle_start_day: 20)
    @expense_category = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true,
                                        starting_balance: 10_000_000)
    @pocket = @user.money_sources.create!(name: "Ahorro", kind: "pocket", active: true,
                                          starting_balance: 0)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    sign_in @user
  end

  def create_template(kind:, amount:, description:)
    category = kind == "income" ? @income_category : @expense_category
    @user.recurring_templates.create!(
      category: category, kind: kind, amount: amount, frequency: "monthly",
      payment_day: 10, active: true, description: description, money_source: @bank
    )
  end

  def create_previous_expense(amount:, date: Date.new(2026, 10, 1))
    @user.expenses.create!(amount: amount, date: date, category: @expense_category,
                           money_source: @bank, description: "variable")
  end

  def seed_projection
    create_template(kind: "income", amount: 10_000_000, description: "Salary")
    create_template(kind: "expense", amount: 3_000_000, description: "Rent")
    create_previous_expense(amount: -1_550_000)
  end

  test "renders the savings capacity projection" do
    travel_to Date.new(2026, 11, 7) do
      seed_projection

      get reports_savings_capacity_path

      assert_response :success
      assert_select "h1", text: "Capacidad de ahorro"
      assert_select "[data-testid=savings-capacity]"
      assert_select "[data-testid=savings-capacity-result]", text: /\$2\.450\.000/
      assert_select "[data-testid=savings-capacity-income]", text: /\$10\.000\.000/
      assert_select "[data-testid=savings-capacity-recurring-expense]", text: /\$3\.000\.000/
      assert_select "[data-testid=savings-capacity-subtotal]", text: /\$7\.000\.000/
      assert_select "[data-testid=savings-capacity-basic-reserve]", text: /\$3\.000\.000/
      assert_select "[data-testid=savings-capacity-previous-variable]", text: /\$1\.550\.000/
      assert_select "select[name=cycle] option[selected]", text: /Próximo ciclo/
      assert_select "input[data-savings-capacity-basic-toggle][checked]"
      assert_select "input[data-savings-capacity-history-toggle][checked]"
      assert_select "input[type=range][data-savings-capacity-percentage][value='30']"
      assert_select "a[data-savings-capacity-goal-link]"
      assert_select "[data-savings-capacity-scenarios]"
      assert_select "a[href='#{reports_savings_capacity_path}']"
      assert_select "a.sidebar-link.active[href='#{reports_savings_capacity_path}']"
      assert_not_includes response.body, "translation_missing"
    end
  end

  test "uses the next future financial cycle by default" do
    travel_to Date.new(2026, 11, 7) do
      get reports_savings_capacity_path

      selected = css_select("select[name=cycle] option[selected]").first
      assert_equal "2026-11-20", selected["value"]
    end
  end

  test "accepts another future cycle and keeps the last closed reference" do
    travel_to Date.new(2026, 11, 7) do
      seed_projection
      second = Reports::SavingsCapacity.future_cycles(@user)[1]

      get reports_savings_capacity_path(cycle: second.starts.iso8601)

      assert_response :success
      assert_select "select[name=cycle] option[selected][value='#{second.starts.iso8601}']"
      assert_select "[data-testid=savings-capacity-result]", text: /\$2\.450\.000/
      assert_select "[data-testid=savings-capacity-previous-variable]", text: /\$1\.550\.000/
      assert_select ".savings-capacity-option-foot", text: /Sep 20 – Oct 19/
    end
  end

  test "falls back to the next future cycle for an invalid cycle param" do
    travel_to Date.new(2026, 11, 7) do
      get reports_savings_capacity_path(cycle: "2020-01-01")

      assert_response :success
      selected = css_select("select[name=cycle] option[selected]").first
      assert_equal "2026-11-20", selected["value"]
    end
  end

  test "accepts the percentage and the option states as params" do
    travel_to Date.new(2026, 11, 7) do
      seed_projection

      get reports_savings_capacity_path(basic_reserve: "0", include_previous_expenses: "0",
                                        basic_reserve_percentage: "50")

      assert_response :success
      assert_select "input[data-savings-capacity-basic-toggle][checked]", count: 0
      assert_select "input[data-savings-capacity-history-toggle][checked]", count: 0
      assert_select "input[type=range][data-savings-capacity-percentage][value='50']"
      assert_select "[data-testid=savings-capacity-result]", text: /\$7\.000\.000/
    end
  end

  test "viewing the report does not change financial records" do
    travel_to Date.new(2026, 11, 7) do
      seed_projection
      balances = [ @bank.reload.balance, @pocket.reload.balance, @card.reload.balance ]

      assert_no_difference [
        -> { Transaction.count }, -> { Transfer.count }, -> { Goal.count },
        -> { GoalAllocation.count }, -> { RecurringTemplate.count }
      ] do
        get reports_savings_capacity_path
      end

      assert_equal balances, [ @bank.reload.balance, @pocket.reload.balance, @card.reload.balance ]
    end
  end

  test "the goal CTA opens the existing goal form with the suggested amount" do
    travel_to Date.new(2026, 11, 7) do
      seed_projection

      get reports_savings_capacity_path

      link = css_select("a[data-savings-capacity-goal-link]").first
      assert link, "goal CTA missing"
      assert_includes link["href"], "/goals/new"
      assert_includes link["href"], "target_amount=2450000"
      assert_includes link["href"], "name="

      get link["href"]

      assert_response :success
      assert_select "form[action='/goals']"
      assert_select "input[name='goal[target_amount]'][value='2.450.000']"
    end
  end

  test "creating a goal from the suggested amount does not move money" do
    travel_to Date.new(2026, 11, 7) do
      seed_projection
      get reports_savings_capacity_path
      link = css_select("a[data-savings-capacity-goal-link]").first
      suggested_amount = 2_450_000

      assert_no_difference [ -> { Transaction.count }, -> { Transfer.count },
                            -> { GoalAllocation.count } ] do
        assert_difference -> { Goal.count }, 1 do
          post goals_path, params: {
            goal: {
              name: "Ahorro del próximo ciclo",
              target_amount: suggested_amount,
              pocket_id: @pocket.id
            }
          }
        end
      end

      assert_redirected_to goals_path
      assert_equal suggested_amount.to_d, Goal.last.target_amount
      assert_equal 0.to_d, @pocket.reload.balance
      assert_includes link["href"], "target_amount=#{suggested_amount}"
    end
  end

  test "requires authentication" do
    sign_out @user

    get reports_savings_capacity_path

    assert_response :redirect
    assert_match(/sign_in/, response.location)
  end

  test "renders empty states when there is no recurring configuration" do
    travel_to Date.new(2026, 11, 7) do
      get reports_savings_capacity_path

      assert_response :success
      assert_select "[data-testid=savings-capacity-income]", text: /\$0/
      assert_select "[data-testid=savings-capacity-recurring-expense]", text: /\$0/
      assert_select "[data-testid=savings-capacity-result]", text: /\$0/
      assert_select "[data-testid=savings-capacity-empty-income]"
      assert_select "[data-testid=savings-capacity-empty-expenses]"
      assert_select "[data-testid=savings-capacity-empty-history]"
    end
  end
end
