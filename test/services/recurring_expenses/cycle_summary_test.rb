# frozen_string_literal: true

require "test_helper"

class RecurringExpenses::CycleSummaryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Recurring Summary User",
      email: "recurring_summary_test@example.com",
      password: "password123"
    )
    @user.update!(financial_cycle_start_day: 20)
    @category = Category.create!(name: "Servicios", is_default: true, category_type: "expense")
    @money_source = @user.money_sources.create!(name: "Cuenta", kind: "account")
    @period = PayCycle.containing(@user, Date.new(2026, 10, 25))
  end

  test "aggregates active recurring expenses for the selected cycle" do
    paid = create_template(description: "Internet", amount: 100_000, payment_day: 25)
    create_payment(paid, amount: 100_000, date: Date.new(2026, 11, 1))
    create_template(description: "Agua", amount: 60_000, payment_day: 5)
    create_template(description: "Inactivo", amount: 80_000, payment_day: 10, active: false)

    summary = build_summary

    assert_equal 160_000.to_d, summary[:monthly_commitment]
    assert_equal 2, summary[:active_count]
    assert_equal 1, summary[:pending_count]
    assert_equal 60_000.to_d, summary[:pending_total]
    assert_equal 1, summary[:paid_count]
    assert_equal 2, summary[:expected_count]
    assert_equal 50, summary[:completion_percentage]
  end

  test "pending total subtracts partial payments" do
    template = create_template(description: "Internet", amount: 100_000, payment_day: 25)
    create_payment(template, amount: 40_000, date: Date.new(2026, 11, 1))

    summary = build_summary

    assert_equal 1, summary[:pending_count]
    assert_equal 60_000.to_d, summary[:pending_total]
  end

  test "next due is the earliest pending occurrence inside the selected cycle" do
    create_template(description: "Agua", amount: 60_000, payment_day: 5)
    create_template(description: "Luz", amount: 90_000, payment_day: 10)

    summary = build_summary

    assert_equal Date.new(2026, 11, 5), summary[:next_due][:date]
    assert_equal "Agua", summary[:next_due][:description]
    assert_equal 60_000.to_d, summary[:next_due][:amount]
  end

  test "next due is nil when every active expense is completed" do
    template = create_template(description: "Internet", amount: 100_000, payment_day: 25)
    create_payment(template, amount: 100_000, date: Date.new(2026, 11, 1))

    summary = build_summary

    assert_nil summary[:next_due]
    assert_equal 100, summary[:completion_percentage]
  end

  test "does not query categories when every pending description is present" do
    create_template(description: "Agua", amount: 60_000, payment_day: 5)
    category_queries = []
    listener = lambda do |_name, _start, _finish, _id, payload|
      category_queries << payload[:sql] if payload[:sql].match?(/FROM "categories"/)
    end

    summary = nil
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
      summary = build_summary
    end

    assert_empty category_queries
    assert_equal "Agua", summary[:next_due][:description]
  end

  test "next due falls back to the category name when the description is blank" do
    create_template(description: "", amount: 60_000, payment_day: 5)

    assert_equal @category.name, build_summary[:next_due][:description]
  end

  test "calendar month periods keep the same due date rules" do
    create_template(description: "Agua", amount: 60_000, payment_day: 5)

    summary = RecurringExpenses::CycleSummary.new(user: @user, period: "2026-10").call

    assert_equal Date.new(2026, 10, 5), summary[:next_due][:date]
  end

  test "does not include another user's recurring expenses" do
    other_user = User.create!(name: "Other", email: "recurring_summary_other@example.com", password: "password123")
    other_category = Category.create!(name: "Other", is_default: true, category_type: "expense")
    RecurringTemplate.create!(
      user: other_user, category: other_category, kind: "expense", amount: 500_000,
      frequency: "monthly", source: "manual", description: "Ajena", payment_day: 5
    )
    create_template(description: "Propia", amount: 60_000, payment_day: 5)

    summary = build_summary

    assert_equal 60_000.to_d, summary[:monthly_commitment]
    assert_equal 1, summary[:active_count]
  end

  private

  def build_summary
    RecurringExpenses::CycleSummary.new(user: @user, period: @period).call
  end

  def create_template(description:, amount:, payment_day:, active: true)
    @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: amount, frequency: "monthly",
      source: "manual", description: description, payment_day: payment_day, active: active
    )
  end

  def create_payment(template, amount:, date:)
    template.transactions.create!(
      user: @user, category: @category, amount: amount, date: date, kind: "expense",
      source: "recurring_template", money_source: @money_source
    )
  end
end
