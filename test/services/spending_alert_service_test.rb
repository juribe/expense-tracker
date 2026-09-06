# frozen_string_literal: true

require "test_helper"

class SpendingAlertServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Alert Engine User",
      email: "spending_alert_service_test@example.com",
      password: "password123"
    )
    @category = Category.create!(
      name: "Transporte_#{SecureRandom.hex(4)}",
      category_type: "expense",
      user: @user
    )
    @current_month = Date.current
  end

  def create_expense(amount, date: @current_month, user: @user, category: @category)
    Expense.create!(user: user, category: category, amount: amount, date: date, description: "test expense")
  end

  def create_budget(monthly_amount)
    Budget.create!(user: @user, category: @category, monthly_amount: monthly_amount, period: "monthly", active: true)
  end

  def alerts_of_kind(kind)
    SpendingAlert.where(user: @user, category: @category, kind: kind)
  end

  test "category spend sums expenses of the user in the category and month" do
    create_expense(400_000)
    create_expense(400_000, date: @current_month.beginning_of_month)
    create_expense(1_000, category: Category.create!(name: "Otra_#{SecureRandom.hex(4)}", category_type: "expense", user: @user))
    create_expense(1_000, date: @current_month.prev_month)
    create_expense(1_000, user: User.create!(name: "Other", email: "other_#{SecureRandom.hex(4)}@example.com", password: "password123"))

    assert_equal 800_000.to_d, CategorySpend.call(user: @user, category: @category, month: @current_month)
  end

  test "creates budget_threshold alert when spend reaches 80% of the budget" do
    create_budget(1_000_000)
    create_expense(800_000)

    assert_equal 1, alerts_of_kind("budget_threshold").count
    alert = alerts_of_kind("budget_threshold").first
    assert_equal 80, alert.pct
    assert_equal 800_000.to_d, alert.amount
    assert_nil alert.previous_amount
    assert_predicate alert.read_at, :nil?
  end

  test "does not alert below the 80% threshold" do
    create_budget(1_000_000)
    create_expense(799_999)

    assert_empty alerts_of_kind("budget_threshold")
    assert_empty SpendingAlert.where(user: @user)
  end

  test "creates budget_exceeded alert when spend reaches 100% of the budget" do
    create_budget(1_000_000)
    create_expense(1_200_000)

    assert_equal 1, alerts_of_kind("budget_exceeded").count
    assert_equal 120, alerts_of_kind("budget_exceeded").first.pct
    assert_empty alerts_of_kind("budget_threshold")
  end

  test "budget alerts are inert when no budget exists" do
    create_expense(5_000_000)

    assert_empty SpendingAlert.where(user: @user)
  end

  test "budget alerts respect the user preference toggles" do
    create_budget(1_000_000)
    @user.alert_prefs.update!(budget_threshold_enabled: false, budget_exceeded_enabled: false)
    create_expense(1_500_000)

    assert_empty SpendingAlert.where(user: @user)
  end

  test "disabling only the threshold toggle still produces exceeded alerts" do
    create_budget(1_000_000)
    @user.alert_prefs.update!(budget_threshold_enabled: false)
    create_expense(1_200_000)

    assert_equal 1, alerts_of_kind("budget_exceeded").count
    assert_empty alerts_of_kind("budget_threshold")
  end

  test "never re-fires: repeated evaluations keep a single alert per kind" do
    create_budget(1_000_000)
    create_expense(850_000)
    create_expense(100_000)
    SpendingAlertService.call(user: @user, category: @category, month: @current_month)
    SpendingAlertService.call(user: @user, category: @category, month: @current_month)

    assert_equal 1, alerts_of_kind("budget_threshold").count
  end

  test "removes the alert when the condition no longer applies" do
    create_budget(1_000_000)
    expense = create_expense(800_000)
    assert_equal 1, alerts_of_kind("budget_threshold").count

    expense.destroy!

    assert_empty SpendingAlert.where(user: @user)
  end

  test "recomputes both months when an expense moves across months" do
    @user.alert_prefs.update!(spending_increase_enabled: true)
    create_budget(1_000_000)
    create_expense(900_000, date: @current_month.prev_month)
    expense = create_expense(900_000, date: @current_month)
    assert_equal 1, alerts_of_kind("budget_threshold").count

    expense.update!(date: @current_month.prev_month.end_of_month)

    assert_empty alerts_of_kind("budget_threshold")
    assert_empty SpendingAlert.where(month: @current_month.strftime("%Y-%m"))
  end

  test "spending_increase alert is off by default" do
    create_expense(100_000, date: @current_month.prev_month)
    create_expense(200_000, date: @current_month)

    assert_empty alerts_of_kind("spending_increase")
  end

  test "creates spending_increase alert at 35% or more vs previous month" do
    @user.alert_prefs.update!(spending_increase_enabled: true)
    create_expense(100_000, date: @current_month.prev_month)
    create_expense(135_000, date: @current_month)

    assert_equal 1, alerts_of_kind("spending_increase").count
    alert = alerts_of_kind("spending_increase").first
    assert_equal 35, alert.pct
    assert_equal 135_000.to_d, alert.amount
    assert_equal 100_000.to_d, alert.previous_amount
  end

  test "spending_increase requires previous month spend" do
    @user.alert_prefs.update!(spending_increase_enabled: true)
    create_expense(500_000, date: @current_month)

    assert_empty alerts_of_kind("spending_increase")
  end

  test "spending_increase alert is removed when spend drops below the increase" do
    @user.alert_prefs.update!(spending_increase_enabled: true)
    create_expense(100_000, date: @current_month.prev_month)
    expense = create_expense(135_000, date: @current_month)
    assert_equal 1, alerts_of_kind("spending_increase").count

    expense.destroy!

    assert_empty alerts_of_kind("spending_increase")
  end

  test "ignores months other than the current month" do
    create_budget(1_000_000)
    @user.alert_prefs.update!(spending_increase_enabled: true)

    SpendingAlertService.call(user: @user, category: @category, month: @current_month.prev_month)

    assert_empty SpendingAlert.where(user: @user)
  end

  test "a brand new user with default preferences never crashes the engine" do
    user = User.create!(name: "Fresh", email: "fresh_#{SecureRandom.hex(4)}@example.com", password: "password123")
    category = Category.create!(name: "Nuevo_#{SecureRandom.hex(4)}", category_type: "expense", user: user)

    assert_nothing_raised do
      SpendingAlertService.call(user: user, category: category, month: Date.current)
    end
    assert_empty SpendingAlert.where(user: user)
  end
end
