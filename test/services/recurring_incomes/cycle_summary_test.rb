# frozen_string_literal: true

require "test_helper"

# RecurringIncomes::CycleSummary calcula el resumen real de la página de
# Ingresos Recurrentes para el ciclo seleccionado: valor mensual esperado,
# pendiente de recibir, dinero efectivamente recibido y próximo ingreso.
class RecurringIncomes::CycleSummaryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Recurring Income Summary User",
      email: "recurring_income_summary_test@example.com",
      password: "password123"
    )
    @user.update!(financial_cycle_start_day: 20)
    @category = Category.create!(name: "Salario Summary", is_default: true, category_type: "income")
    @money_source = @user.money_sources.create!(name: "Cuenta Ingresos", kind: "account")
    @period = PayCycle.containing(@user, Date.new(2026, 10, 25))
  end

  test "aggregates active recurring incomes for the selected cycle" do
    received = create_template(description: "Salario", amount: 1_000_000, payment_day: 25)
    create_payment(received, amount: 1_000_000, date: Date.new(2026, 11, 1))
    create_template(description: "Freelance", amount: 500_000, payment_day: 5)
    create_template(description: "Inactivo", amount: 300_000, payment_day: 10, active: false)

    summary = build_summary

    assert_equal 1_500_000.to_d, summary[:monthly_expected]
    assert_equal 2, summary[:active_count]
    assert_equal 1, summary[:pending_count]
    assert_equal 500_000.to_d, summary[:pending_total]
    assert_equal 1_000_000.to_d, summary[:received_total]
    assert_equal 1, summary[:received_count]
    assert_equal 2, summary[:expected_count]
    assert_equal 50, summary[:completion_percentage]
  end

  test "partial receipts reduce pending total and count as received money" do
    template = create_template(description: "Salario", amount: 1_000_000, payment_day: 25)
    create_payment(template, amount: 400_000, date: Date.new(2026, 11, 1))

    summary = build_summary

    assert_equal 600_000.to_d, summary[:pending_total]
    assert_equal 400_000.to_d, summary[:received_total]
    assert_equal 1, summary[:pending_count]
    assert_equal 0, summary[:received_count]
  end

  test "next income is the earliest pending occurrence inside the selected cycle" do
    create_template(description: "Freelance", amount: 500_000, payment_day: 5)
    create_template(description: "Salario", amount: 1_000_000, payment_day: 10)

    summary = build_summary

    assert_equal Date.new(2026, 11, 5), summary[:next_income][:date]
    assert_equal "Freelance", summary[:next_income][:description]
    assert_equal 500_000.to_d, summary[:next_income][:amount]
  end

  test "next income is nil when every active income is received" do
    template = create_template(description: "Salario", amount: 1_000_000, payment_day: 25)
    create_payment(template, amount: 1_000_000, date: Date.new(2026, 11, 1))

    summary = build_summary

    assert_nil summary[:next_income]
    assert_equal 100, summary[:completion_percentage]
  end

  test "does not include inactive templates or another user's incomes" do
    other_user = User.create!(name: "Other", email: "recurring_income_other@example.com",
                              password: "password123")
    other_category = Category.create!(name: "Other Income", is_default: true, category_type: "income")
    RecurringTemplate.create!(
      user: other_user, category: other_category, kind: "income", amount: 9_000_000,
      frequency: "monthly", source: "manual", description: "Ajena", payment_day: 5
    )
    create_template(description: "Propia", amount: 1_000_000, payment_day: 5)
    create_template(description: "Inactivo", amount: 800_000, payment_day: 10, active: false)

    summary = build_summary

    assert_equal 1_000_000.to_d, summary[:monthly_expected]
    assert_equal 1, summary[:active_count]
  end

  test "calendar month periods keep the same due date rules" do
    create_template(description: "Freelance", amount: 500_000, payment_day: 5)

    summary = RecurringIncomes::CycleSummary.new(user: @user, period: "2026-10").call

    assert_equal Date.new(2026, 10, 5), summary[:next_income][:date]
  end

  test "next income falls back to the category name when description is blank" do
    create_template(description: "", amount: 500_000, payment_day: 5)

    assert_equal @category.name, build_summary[:next_income][:description]
  end

  private

  def build_summary
    RecurringIncomes::CycleSummary.new(user: @user, period: @period).call
  end

  def create_template(description:, amount:, payment_day:, active: true)
    @user.recurring_templates.create!(
      category: @category, kind: "income", amount: amount, frequency: "monthly",
      source: "manual", description: description, payment_day: payment_day, active: active
    )
  end

  def create_payment(template, amount:, date:)
    template.transactions.create!(
      user: @user, category: @category, amount: amount, date: date, kind: "income",
      source: "recurring_template", money_source: @money_source
    )
  end
end
