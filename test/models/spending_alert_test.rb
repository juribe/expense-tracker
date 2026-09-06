# frozen_string_literal: true

require "test_helper"

class SpendingAlertTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Alert User",
      email: "spending_alert_test@example.com",
      password: "password123"
    )
    @category = Category.create!(
      name: "Restaurantes_#{SecureRandom.hex(4)}",
      category_type: "expense",
      user: @user
    )
    @current_month = Time.zone.today.strftime("%Y-%m")
  end

  test "is valid with user, category, kind, month, pct and amount" do
    alert = SpendingAlert.create!(
      user: @user,
      category: @category,
      kind: "budget_threshold",
      month: @current_month,
      pct: 82,
      amount: 800_000
    )
    assert alert.persisted?
    assert_equal @user, alert.user
    assert_equal @category, alert.category
  end

  test "rejects a kind outside KINDS" do
    alert = SpendingAlert.new(user: @user, category: @category, kind: "other", month: @current_month, pct: 50, amount: 1)
    assert_not alert.valid?
    assert_includes alert.errors[:kind], "no está incluido en la lista"
  end

  test "requires kind, month and pct" do
    alert = SpendingAlert.new(user: @user, category: @category, amount: 1)
    assert_not alert.valid?
    assert alert.errors[:kind].any?
    assert alert.errors[:month].any?
    assert alert.errors[:pct].any?
  end

  test "unread scope returns only alerts with no read_at" do
    read_alert = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 800_000, read_at: Time.current)
    unread_alert = SpendingAlert.create!(user: @user, category: @category, kind: "budget_exceeded", month: @current_month, pct: 105, amount: 1_050_000)

    assert_includes SpendingAlert.unread, unread_alert
    assert_not_includes SpendingAlert.unread, read_alert
  end

  test "budget scope returns threshold and exceeded kinds only" do
    threshold = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 800_000)
    exceeded = SpendingAlert.create!(user: @user, category: @category, kind: "budget_exceeded", month: @current_month, pct: 100, amount: 1_000_000)
    increase = SpendingAlert.create!(user: @user, category: @category, kind: "spending_increase", month: @current_month, pct: 40, amount: 700_000)

    assert_includes SpendingAlert.budget, threshold
    assert_includes SpendingAlert.budget, exceeded
    assert_not_includes SpendingAlert.budget, increase
  end

  test "spending scope returns only spending_increase kind" do
    increase = SpendingAlert.create!(user: @user, category: @category, kind: "spending_increase", month: @current_month, pct: 40, amount: 700_000)
    threshold = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 800_000)

    assert_includes SpendingAlert.spending, increase
    assert_not_includes SpendingAlert.spending, threshold
  end

  test "for_month and for_current_month match the YYYY-MM period" do
    current = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 800_000)
    past = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: Time.zone.today.prev_month.strftime("%Y-%m"), pct: 80, amount: 800_000)

    assert_equal [ current ], SpendingAlert.for_current_month.to_a
    assert_includes SpendingAlert.for_month(Time.zone.today.prev_month), past
    assert_not_includes SpendingAlert.for_month(Time.zone.today.prev_month), current
  end

  test "budget? is true only for budget kinds" do
    threshold = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 800_000)
    increase = SpendingAlert.create!(user: @user, category: @category, kind: "spending_increase", month: @current_month, pct: 40, amount: 700_000)

    assert threshold.budget?
    assert_not increase.budget?
  end

  test "budget_amount returns the category budget for budget kinds" do
    budget = Budget.create!(user: @user, category: @category, monthly_amount: 1_000_000, period: "monthly", active: true)
    threshold = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 800_000)
    increase = SpendingAlert.create!(user: @user, category: @category, kind: "spending_increase", month: @current_month, pct: 40, amount: 700_000)

    assert_equal budget.monthly_amount, threshold.budget_amount
    assert_nil increase.budget_amount
  end

  test "read? reflects read_at" do
    alert = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 800_000)
    assert_not alert.read?
    alert.update!(read_at: Time.current)
    assert alert.read?
  end

  test "destroying the category removes its alerts" do
    alert = SpendingAlert.create!(user: @user, category: @category, kind: "budget_threshold", month: @current_month, pct: 80, amount: 800_000)
    @category.destroy!
    assert_not SpendingAlert.exists?(alert.id)
  end
end
