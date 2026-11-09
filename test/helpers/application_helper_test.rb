# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "available_credit_for subtracts debt from the credit limit" do
    assert_equal 9000000, available_credit_for({ "credit_limit" => "10000000", "balance" => "1000000" })
  end

  test "available_credit_for floors at zero" do
    assert_equal 0, available_credit_for({ "credit_limit" => "500000", "balance" => "2000000" })
  end

  test "available_credit_for returns zero without a credit limit" do
    assert_equal 0, available_credit_for({ "balance" => "100000" })
  end

  test "money_field_value renders Colombian number format" do
    assert_equal "67.429.112,92", money_field_value(67429112.92)
    assert_equal "5.734.980", money_field_value("5734980")
    assert_equal "", money_field_value(nil)
  end

  test "chart_money_options uses whole-peso Colombian format for chart tooltips" do
    assert_equal({ prefix: "$", thousands: ".", decimal: ",", round: 0 }, chart_money_options)
  end

  test "user_display_name prefers the stored name over the email local part" do
    assert_equal "José Uribe", user_display_name(User.new(name: "José Uribe", email: "jse.uribe@gmail.com"))
  end

  test "user_display_name falls back to the email local part when the name is blank" do
    assert_equal "jse.uribe", user_display_name(User.new(name: "", email: "jse.uribe@gmail.com"))
  end

  test "user_initials takes the first letters of the first two name words" do
    assert_equal "JU", user_initials(User.new(name: "José Uribe", email: "jse.uribe@gmail.com"))
    assert_equal "J", user_initials(User.new(name: "Josefa", email: "jse.uribe@gmail.com"))
  end

  test "user_initials falls back to the first two email characters without a name" do
    assert_equal "JS", user_initials(User.new(name: "", email: "jse.uribe@gmail.com"))
  end

  setup do
    @user = User.create!(name: "Test User", email: "app_helper_loans@example.com", password: "password123")
    @loan = @user.money_sources.create!(name: "Crédito Hipotecario en Pesos", kind: "loan", bank: "Davibank", active: true)
    @loan.build_credit_account(
      principal_amount: 170900000, outstanding_balance: 66959723, installment_amount: 1130642,
      installment_count: 192, installments_paid: 75, interest_rate: 18.05,
      interest_rate_type: "effective_annual", payment_frequency: "monthly", start_date: Date.new(2020, 1, 15)
    )
    @loan.save!
  end

  test "loan_identity picks the accent and icon by loan type" do
    assert_equal({ icon: "home", accent: "accent-purple" }, loan_identity(@loan))
    assert_equal({ icon: "rotate", accent: "accent-teal" },
                 loan_identity(@user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", starting_balance: 0)))
    assert_equal({ icon: "car", accent: "accent-amber" },
                 loan_identity(@user.money_sources.create!(name: "Crédito de Vehículo", kind: "loan", starting_balance: 0)))
  end

  test "loan_summary aggregates outstanding balance, active count, remaining and monthly payments" do
    second = @user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", starting_balance: 0, active: true)
    second.build_credit_account(principal_amount: 53049762, outstanding_balance: 53900000,
                                installment_amount: 1145600, installment_count: 48, installments_paid: 18)
    second.save!

    summary = loan_summary(@user.money_sources.where(kind: "loan").to_a)
    assert_equal BigDecimal("120859723"), summary[:total_balance]
    assert_equal 2, summary[:active_count]
    assert_equal BigDecimal("2276242"), summary[:next_30d]
    assert summary[:remaining].positive?
  end

  test "loan_summary is safe with loans that have no credit account" do
    bare = @user.money_sources.create!(name: "Préstamo", kind: "loan", starting_balance: 0, active: true)
    summary = loan_summary([ bare ])
    assert_equal 0, summary[:total_balance]
    assert_equal 1, summary[:active_count]
    assert_equal 0, summary[:remaining]
    assert_equal 0, summary[:next_30d]
  end

  test "next_payment_date prefers a scheduled recurring template payment day" do
    templ = @user.recurring_templates.create!(
      category: Category.create!(name: "Cuotas", is_default: true),
      kind: "expense", amount: 1000, frequency: "monthly", source: "wizard",
      money_source: @loan, payment_day: 20
    )
    date = next_payment_date(@loan)
    assert_kind_of Date, date
    assert_equal 20, date.day
  end

  test "next_payment_date falls back to deriving from start date and frequency" do
    @loan.recurring_templates.destroy_all
    date = next_payment_date(@loan)
    assert_kind_of Date, date
  end

  test "pocket_money_summary reflects real balances and allocation shares" do
    pocket = @user.money_sources.create!(name: "Bolsillo Viaje", kind: "pocket", starting_balance: 1_000_000)
    goal = Goal.create!(user: @user, pocket: pocket, name: "Viaje", target_amount: 500_000)
    GoalAllocation.create!(financial_goal: goal, pocket: pocket, amount: 250_000, date: Date.current)

    summary = pocket_money_summary(pocket)

    assert_equal BigDecimal("1000000"), summary[:total]
    assert_equal BigDecimal("250000"), summary[:allocated]
    assert_equal BigDecimal("750000"), summary[:unallocated]
    assert_equal 25, summary[:allocated_percentage]
    assert_equal 75, summary[:unallocated_percentage]
  end

  test "pocket_money_summary returns zero shares for an empty pocket" do
    pocket = @user.money_sources.create!(name: "Bolsillo Vacío", kind: "pocket", starting_balance: 0)

    summary = pocket_money_summary(pocket)

    assert_equal BigDecimal("0"), summary[:total]
    assert_equal BigDecimal("0"), summary[:allocated]
    assert_equal BigDecimal("0"), summary[:unallocated]
    assert_equal 0, summary[:allocated_percentage]
    assert_equal 0, summary[:unallocated_percentage]
  end

  test "goals_summary aggregates saved, target, remaining and progress" do
    pocket = @user.money_sources.create!(name: "Bolsillo Metas", kind: "pocket", starting_balance: 10_000_000)
    travel = Goal.create!(user: @user, pocket: pocket, name: "Viaje", target_amount: 5_000_000)
    emergency = Goal.create!(user: @user, pocket: pocket, name: "Emergencias", target_amount: 3_000_000)
    GoalAllocation.create!(financial_goal: travel, pocket: pocket, amount: 2_000_000, date: Date.current)
    GoalAllocation.create!(financial_goal: emergency, pocket: pocket, amount: 1_000_000, date: Date.current)

    summary = goals_summary([ travel, emergency ])

    assert_equal 2, summary[:count]
    assert_equal BigDecimal("3000000"), summary[:total_saved]
    assert_equal BigDecimal("8000000"), summary[:total_target]
    assert_equal BigDecimal("5000000"), summary[:remaining]
    assert_in_delta 37.5, summary[:progress_percentage], 0.01
  end

  test "goals_summary caps the progress at 100 percent and floors remaining at zero" do
    pocket = @user.money_sources.create!(name: "Bolsillo Excedido", kind: "pocket", starting_balance: 10_000_000)
    goal = Goal.create!(user: @user, pocket: pocket, name: "Viaje", target_amount: 2_000_000)
    GoalAllocation.create!(financial_goal: goal, pocket: pocket, amount: 3_000_000, date: Date.current)

    summary = goals_summary([ goal ])

    assert_equal BigDecimal("3000000"), summary[:total_saved]
    assert_equal 100, summary[:progress_percentage]
    assert_equal BigDecimal("0"), summary[:remaining]
  end

  test "goals_summary handles an empty collection without dividing by zero" do
    summary = goals_summary([])

    assert_equal 0, summary[:count]
    assert_equal BigDecimal("0"), summary[:total_saved]
    assert_equal BigDecimal("0"), summary[:total_target]
    assert_equal BigDecimal("0"), summary[:remaining]
    assert_equal 0, summary[:progress_percentage]
  end
end
