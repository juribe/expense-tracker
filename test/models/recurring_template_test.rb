# frozen_string_literal: true

require "test_helper"

# Cycle-aware extras of RecurringTemplate: period status for pay cycles.
class RecurringTemplateTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Template User", email: "recurring_template_test@example.com", password: "password123")
    @money_source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000_000)
    @category = Category.create!(name: "Servicios", is_default: false, category_type: "expense", user: @user)
    @template = @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: 50_000, frequency: "monthly",
      source: "manual", description: "Arriendo"
    )
  end

  test "status_for accepts a pay-cycle range" do
    cycle = Date.new(2026, 10, 20)..Date.new(2026, 11, 19)

    assert_equal :pending, @template.status_for(cycle)

    @template.transactions.create!(user: @user, category: @category, amount: 50_000, date: Date.new(2026, 11, 3),
                                   kind: "expense", source: "recurring_template", money_source: @money_source)

    assert_equal :completed, @template.status_for(cycle)
  end

  test "status_for accepts a PayCycle::Cycle object" do
    user_with_schedule = @user
    user_with_schedule.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.containing(user_with_schedule, Date.new(2026, 10, 25))

    assert_equal :pending, @template.status_for(cycle)

    @template.transactions.create!(user: @user, category: @category, amount: 50_000, date: Date.new(2026, 11, 4),
                                   kind: "expense", source: "recurring_template", money_source: @money_source)

    assert_equal :completed, @template.status_for(cycle)
  end

  test "calendar month status is unaffected by the cycle extension" do
    @template.transactions.create!(user: @user, category: @category, amount: 50_000, date: Date.new(2026, 10, 15),
                                   kind: "expense", source: "recurring_template", money_source: @money_source)

    assert_equal :completed, @template.status_for("2026-10")
    assert_equal :pending, @template.status_for("2026-09")
  end

  test "inactive templates are inactive in every period shape" do
    @template.update!(active: false)

    assert_equal :inactive, @template.status_for(Date.new(2026, 10, 20)..Date.new(2026, 11, 19))
    assert_equal :inactive, @template.status_for("2026-10")
  end

  test "a foreign category is invalid" do
    other_user = User.create!(name: "Other", email: "recurring_foreign_category_model@example.com",
                              password: "password123")
    foreign_category = Category.create!(name: "Ajena Modelo", is_default: false, category_type: "expense",
                                        user: other_user)
    template = @user.recurring_templates.build(category: foreign_category, kind: "expense", amount: 50_000,
                                               frequency: "monthly", source: "manual")

    assert_not template.valid?
    assert_includes template.errors[:category], I18n.t("activerecord.errors.messages.other_user")
  end

  test "a foreign money source is invalid" do
    other_user = User.create!(name: "Other", email: "recurring_foreign_source_model@example.com",
                              password: "password123")
    foreign_source = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account")
    template = @user.recurring_templates.build(category: @category, kind: "expense", amount: 50_000,
                                               frequency: "monthly", source: "manual",
                                               money_source: foreign_source)

    assert_not template.valid?
    assert_includes template.errors[:money_source], I18n.t("activerecord.errors.messages.other_user")
  end

  test "a shared category with an own money source is valid" do
    shared_category = Category.create!(name: "Arriendo Compartido", is_default: true, category_type: "expense")
    template = @user.recurring_templates.build(category: shared_category, kind: "expense", amount: 50_000,
                                               frequency: "monthly", source: "manual",
                                               money_source: @money_source)

    assert template.valid?
  end

  test "income status counts manual receipts in the same category" do
    income_category = Category.create!(name: "Salario recurrente", is_default: false,
                                       category_type: "income", user: @user)
    template = create_income_template(income_category, amount: 2_000_000)
    period = Date.new(2026, 10, 1)..Date.new(2026, 10, 31)

    template.transactions.create!(user: @user, category: income_category, amount: 1_000_000,
                                  date: Date.new(2026, 10, 5), kind: "income",
                                  source: "recurring_template", money_source: @money_source)
    manual = @user.incomes.create!(amount: 1_000_000, description: "Segundo pago",
                                   date: Date.new(2026, 10, 25), category: income_category,
                                   money_source: @money_source)

    assert_equal 2_000_000.to_d, template.paid_amount_for_period(period)
    assert_equal :completed, template.status_for(period)
    assert_equal manual.id, template.last_occurrence.id
  end

  test "manual income in another category does not complete an income template" do
    income_category = Category.create!(name: "Salario categoría", is_default: false,
                                       category_type: "income", user: @user)
    other_category = Category.create!(name: "Inversiones categoría", is_default: false,
                                      category_type: "income", user: @user)
    template = create_income_template(income_category, amount: 2_000_000)
    period = Date.new(2026, 10, 1)..Date.new(2026, 10, 31)

    template.transactions.create!(user: @user, category: income_category, amount: 1_000_000,
                                  date: Date.new(2026, 10, 5), kind: "income",
                                  source: "recurring_template", money_source: @money_source)
    @user.incomes.create!(amount: 1_000_000, description: "Otro ingreso",
                          date: Date.new(2026, 10, 25), category: other_category,
                          money_source: @money_source)

    assert_equal 1_000_000.to_d, template.paid_amount_for_period(period)
    assert_equal :pending, template.status_for(period)
  end

  test "manual income is ambiguous when another active income template shares the category" do
    income_category = Category.create!(name: "Salario compartido", is_default: false,
                                       category_type: "income", user: @user)
    salary = create_income_template(income_category, amount: 2_000_000, description: "Salario")
    create_income_template(income_category, amount: 1_000_000, description: "Bono")
    period = Date.new(2026, 10, 1)..Date.new(2026, 10, 31)

    @user.incomes.create!(amount: 2_000_000, description: "Pago",
                          date: Date.new(2026, 10, 25), category: income_category,
                          money_source: @money_source)

    assert_equal 0.to_d, salary.paid_amount_for_period(period)
    assert_equal :pending, salary.status_for(period)
  end

  test "manual income outside the period does not complete an income template" do
    income_category = Category.create!(name: "Salario fuera", is_default: false,
                                       category_type: "income", user: @user)
    template = create_income_template(income_category, amount: 2_000_000)
    period = Date.new(2026, 10, 1)..Date.new(2026, 10, 31)

    @user.incomes.create!(amount: 2_000_000, description: "Pago anterior",
                          date: Date.new(2026, 9, 30), category: income_category,
                          money_source: @money_source)

    assert_equal 0.to_d, template.paid_amount_for_period(period)
    assert_equal :pending, template.status_for(period)
  end

  private

  def create_income_template(category, amount:, description: "Salario")
    @user.recurring_templates.create!(
      category: category, kind: "income", amount: amount, frequency: "monthly",
      source: "manual", description: description, payment_day: 5, money_source: @money_source
    )
  end
end
