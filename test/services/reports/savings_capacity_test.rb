# frozen_string_literal: true

require "test_helper"

class ReportsSavingsCapacityTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Savings Capacity", email: "savings_capacity_test@example.com",
                         password: "password123")
    @user.update!(financial_cycle_start_day: 20)
    @expense_category = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true,
                                        starting_balance: 10_000_000)
    @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", active: true,
                                        starting_balance: 2_000_000)
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", active: true)
    @loan = @user.money_sources.create!(name: "Crédito", kind: "loan", active: true)
    @other = User.create!(name: "Other Savings", email: "savings_capacity_other@example.com",
                          password: "password123")
    @other_bank = @other.money_sources.create!(name: "Other Bank", kind: "account", active: true,
                                               starting_balance: 10_000_000)
  end

  def report_for(cycle: nil, percentage: 30, basic: true, history: true, user: @user)
    filter = Reports::Filter.new(user: user, period: Reports::Period.new(user: user))
    Reports::SavingsCapacity.new(
      user: user,
      filter: filter,
      cycle: cycle,
      basic_reserve_enabled: basic,
      include_previous_expenses: history,
      basic_reserve_percentage: percentage
    ).call
  end

  def template(kind:, amount:, description:, payment_day: 10, active: true, user: @user)
    category = kind == "income" ? @income_category : @expense_category
    source = user == @user ? @bank : @other_bank
    RecurringTemplate.create!(
      user: user, category: category, kind: kind, amount: amount, frequency: "monthly",
      payment_day: payment_day, active: active, description: description, money_source: source
    )
  end

  def expense(amount:, date:, user: @user, source: nil, category: @expense_category,
              recurring_template: nil, source_name: "manual")
    source ||= user == @user ? @bank : @other_bank
    Expense.create!(
      user: user, category: category, money_source: source, amount: amount, date: date,
      description: "expense", recurring_template: recurring_template, source: source_name
    )
  end

  def next_cycle
    Reports::SavingsCapacity.future_cycles(@user).first
  end

  def second_future_cycle
    Reports::SavingsCapacity.future_cycles(@user)[1]
  end

  test "defaults to the next financial cycle" do
    travel_to Date.new(2026, 11, 7) do
      report = report_for

      assert_equal Date.new(2026, 11, 20), report[:cycle].starts
      assert_equal Date.new(2026, 12, 19), report[:cycle].ends
    end
  end

  test "sums only active recurring incomes for the selected cycle" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 5_000_000, description: "Salary")
      template(kind: "income", amount: 9_000_000, description: "Old salary", active: false)
      Income.create!(user: @user, category: @income_category, money_source: @bank,
                     amount: 8_000_000, date: Date.new(2026, 11, 1), description: "Actual income")

      report = report_for

      assert_equal 5_000_000.to_d, report[:income_total]
    end
  end

  test "sums only active recurring expenses for the selected cycle" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "expense", amount: 1_000_000, description: "Rent")
      template(kind: "expense", amount: 500_000, description: "Internet")
      template(kind: "expense", amount: 2_000_000, description: "Old rent", active: false)
      expense(amount: -3_000_000, date: Date.new(2026, 11, 1))

      report = report_for

      assert_equal 1_500_000.to_d, report[:recurring_expense_total]
    end
  end

  test "computes the available amount after recurring commitments" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 5_000_000, description: "Salary")
      template(kind: "expense", amount: 1_500_000, description: "Rent")

      report = report_for

      assert_equal 3_500_000.to_d, report[:after_recurring_total]
    end
  end

  test "applies the basic reserve percentage to projected recurring income" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")

      report = report_for(percentage: 30, basic: true, history: false)

      assert_equal 3_000_000.to_d, report[:default_scenario][:basic_reserve]
      assert_equal 4_000_000.to_d, report[:default_scenario][:result]
    end
  end

  test "changing the percentage changes the reserve and the result" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")

      twenty = report_for(percentage: 20, history: false)
      fifty = report_for(percentage: 50, history: false)

      assert_equal 2_000_000.to_d, twenty[:default_scenario][:basic_reserve]
      assert_equal 5_000_000.to_d, twenty[:default_scenario][:result]
      assert_equal 5_000_000.to_d, fifty[:default_scenario][:basic_reserve]
      assert_equal 2_000_000.to_d, fifty[:default_scenario][:result]
    end
  end

  test "disabling the basic reserve sets it to zero" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")

      report = report_for(basic: false, history: false)

      assert_equal 0.to_d, report[:default_scenario][:basic_reserve]
      assert_equal 7_000_000.to_d, report[:default_scenario][:result]
    end
  end

  test "includes the last closed cycle non-recurring variable expenses" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")
      expense(amount: -1_550_000, date: Date.new(2026, 10, 1))

      report = report_for(percentage: 30, history: true)

      assert_equal Date.new(2026, 9, 20), report[:reference_cycle].starts
      assert_equal Date.new(2026, 10, 19), report[:reference_cycle].ends
      assert_equal 1_550_000.to_d, report[:previous_variable_total]
      assert_equal 1, report[:previous_variable_count]
      assert_equal 2_450_000.to_d, report[:default_scenario][:result]
    end
  end

  test "does not use the current in-progress cycle as the reference" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")
      expense(amount: -900_000, date: Date.new(2026, 11, 1))

      report = report_for(history: true)

      assert_equal Date.new(2026, 9, 20), report[:reference_cycle].starts
      assert_equal 0.to_d, report[:previous_variable_total]
    end
  end

  test "excludes recurring, debt-payment and internal-transfer movements from the reference" do
    travel_to Date.new(2026, 11, 7) do
      recurring = template(kind: "expense", amount: 500_000, description: "Netflix")
      expense(amount: -500_000, date: Date.new(2026, 10, 2), recurring_template: recurring,
              source_name: "recurring_template")

      card_expense = expense(amount: -800_000, date: Date.new(2026, 10, 3), source: @card)
      Payment.create!(user: @user, expense: card_expense, money_source: @loan,
                      amount: 800_000, principal_amount: 800_000)

      expense(amount: -300_000, date: Date.new(2026, 10, 4), source_name: "recurring_template")
      expense(amount: -200_000, date: Date.new(2026, 10, 5))

      Transfer.create!(user: @user, from_source: @bank, to_source: @cash,
                       amount: 1_000_000, date: Date.new(2026, 10, 6))

      report = report_for(history: true)

      assert_equal 200_000.to_d, report[:previous_variable_total]
      assert_equal 1, report[:previous_variable_count]
    end
  end

  test "disabling the historical reference does not discount previous expenses" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")
      expense(amount: -1_550_000, date: Date.new(2026, 10, 1))

      report = report_for(percentage: 30, basic: true, history: false)

      assert_equal 1_550_000.to_d, report[:previous_variable_total]
      assert_equal 0.to_d, report[:default_scenario][:previous_variable]
      assert_equal 4_000_000.to_d, report[:default_scenario][:result]
    end
  end

  test "changing the selected cycle keeps the last closed cycle as the reference" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")
      expense(amount: -2_000_000, date: Date.new(2026, 9, 25))
      expense(amount: -1_000_000, date: Date.new(2026, 11, 1))

      next_report = report_for(cycle: next_cycle, history: true)
      following_report = report_for(cycle: second_future_cycle, history: true)

      assert_equal Date.new(2026, 11, 20), next_report[:cycle].starts
      assert_equal 2_000_000.to_d, next_report[:previous_variable_total]
      assert_equal Date.new(2026, 12, 20), following_report[:cycle].starts
      assert_equal 2_000_000.to_d, following_report[:previous_variable_total]
      assert_equal Date.new(2026, 9, 20), following_report[:reference_cycle].starts
    end
  end

  test "returns a negative result without clamping it" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 1_000_000, description: "Salary")
      template(kind: "expense", amount: 500_000, description: "Rent")
      expense(amount: -1_000_000, date: Date.new(2026, 10, 1))

      report = report_for(percentage: 30, basic: true, history: true)

      assert_equal(-800_000.to_d, report[:default_scenario][:result])
      assert report[:default_scenario][:result].negative?
    end
  end

  test "returns zero historical reference when the previous cycle has no variable expenses" do
    travel_to Date.new(2026, 11, 7) do
      report = report_for(history: true)

      assert_equal 0.to_d, report[:previous_variable_total]
      assert_equal 0, report[:previous_variable_count]
      assert_equal 0.to_d, report[:default_scenario][:result]
    end
  end

  test "isolates recurring and historical data by user" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 5_000_000, description: "Mine")
      template(kind: "income", amount: 9_000_000, description: "Theirs", user: @other)
      template(kind: "expense", amount: 1_000_000, description: "Mine expense")
      template(kind: "expense", amount: 8_000_000, description: "Theirs expense", user: @other)
      expense(amount: -400_000, date: Date.new(2026, 10, 1))
      expense(amount: -7_000_000, date: Date.new(2026, 10, 1), user: @other)

      report = report_for(history: true)

      assert_equal 5_000_000.to_d, report[:income_total]
      assert_equal 1_000_000.to_d, report[:recurring_expense_total]
      assert_equal 400_000.to_d, report[:previous_variable_total]
    end
  end

  test "does not create or modify financial records" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")
      expense(amount: -1_550_000, date: Date.new(2026, 10, 1))

      balances = [ @bank.reload.balance, @cash.reload.balance, @card.reload.balance, @loan.reload.balance ]

      assert_no_difference [
        -> { Transaction.count }, -> { Transfer.count }, -> { Payment.count },
        -> { Goal.count }, -> { GoalAllocation.count }, -> { RecurringTemplate.count }
      ] do
        report_for(history: true)
      end

      assert_equal balances, [ @bank.reload.balance, @cash.reload.balance,
                               @card.reload.balance, @loan.reload.balance ]
    end
  end

  test "reference cycle is always a closed cycle" do
    travel_to Date.new(2026, 11, 7) do
      report = report_for(cycle: next_cycle)

      assert report[:reference_cycle].ends < Date.current
    end

    travel_to Date.new(2026, 11, 20) do
      report = report_for

      assert_equal Date.new(2026, 10, 20), report[:reference_cycle].starts
      assert report[:reference_cycle].ends < Date.current
    end
  end

  test "normalizes the percentage to the supported range" do
    travel_to Date.new(2026, 11, 7) do
      assert_equal 30, report_for(percentage: 32)[:percentage]
      assert_equal 30, report_for(percentage: 0)[:percentage]
      assert_equal 50, report_for(percentage: 60)[:percentage]
      assert_equal 5, report_for(percentage: 2)[:percentage]
    end
  end

  test "exposes a scenario for every percentage and option combination" do
    travel_to Date.new(2026, 11, 7) do
      template(kind: "income", amount: 10_000_000, description: "Salary")
      template(kind: "expense", amount: 3_000_000, description: "Rent")
      expense(amount: -1_550_000, date: Date.new(2026, 10, 1))

      report = report_for(percentage: 30, basic: true, history: true)

      assert_equal 40, report[:scenarios].size
      assert_equal (5..50).step(5).to_a, report[:scenarios].map { |row| row[:percentage] }.uniq
      default = report[:default_scenario]
      assert_equal 30, default[:percentage]
      assert default[:basic_reserve_enabled]
      assert default[:include_previous]
      assert_equal 2_450_000.to_d, default[:result]
    end
  end
end
