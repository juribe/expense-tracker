# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesConfiguredRecurringTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Configured User", email: "savings_configured@example.com", password: "password123")
    @category = Category.create!(name: "Suscripciones configuradas", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
  end

  def template(description:, amount:, kind: "expense", active: true, frequency: "monthly",
               payment_day: 12, user: @user, category: @category)
    RecurringTemplate.create!(user: user, category: category, kind: kind, description: description,
                              amount: amount, frequency: frequency, source: "manual",
                              active: active, payment_day: payment_day)
  end

  def report
    SavingsOpportunities::ConfiguredRecurring.new(user: @user).call
  end

  test "builds rows from active expense templates only" do
    netflix = template(description: "Netflix", amount: 29_900)
    template(description: "Salario", amount: 5_000_000, kind: "income")
    template(description: "Servicio antiguo", amount: 10_000, active: false)

    data = report
    row = data[:rows].first

    assert_equal 1, data[:rows].size
    assert_equal netflix.id, row[:template_id]
    assert_equal "Netflix", row[:name]
    assert_equal 29_900.to_d, row[:amount]
    assert_equal 29_900.to_d, row[:monthly_amount]
    assert_equal "monthly", row[:frequency]
    assert_equal 12, row[:payment_day]
    assert_equal :configured, row[:confidence]
    assert_equal "configured", data[:source]
    assert_equal 1, data[:possible_count]
    assert_equal 0, data[:confirmed_count]
  end

  test "converts non-monthly frequencies to a monthly equivalent" do
    template(description: "Semanario", amount: 10_000, frequency: "weekly")

    data = report

    assert_in_delta 43_333.33, data[:rows].first[:monthly_amount].to_f, 0.01
    assert_in_delta 43_333.33, data[:total_monthly].to_f, 0.01
  end

  test "sorts rows by monthly amount and totals every configured payment" do
    template(description: "Pequeño", amount: 20_000)
    template(description: "Grande", amount: 300_000)

    data = report

    assert_equal [ "Grande", "Pequeño" ], data[:rows].map { |row| row[:name] }
    assert_equal 320_000.to_d, data[:total_monthly]
  end

  test "includes linked movements and the last payment date" do
    configured = template(description: "Gimnasio", amount: 200_000)
    Expense.create!(user: @user, category: @category, money_source: @bank, amount: -200_000,
                    date: Date.new(2026, 10, 5), description: "Gimnasio",
                    recurring_template: configured)

    row = report[:rows].first

    assert_equal Date.new(2026, 10, 5), row[:last_date]
    assert_equal 1, row[:occurrences]
    assert_equal 1, row[:movements].size
    assert_equal 200_000.to_d, row[:movements].first[:amount]
  end

  test "falls back to the category name when the template has no description" do
    template(description: nil, amount: 50_000)

    assert_equal @category.name, report[:rows].first[:name]
  end

  test "scopes configuration to the user" do
    other = User.create!(name: "Other", email: "savings_configured_other@example.com", password: "password123")
    other_category = Category.create!(name: "Otra", is_default: true, category_type: "expense")
    template(description: "Ajeno", amount: 10_000, user: other, category: other_category)

    assert_empty report[:rows]
  end
end
