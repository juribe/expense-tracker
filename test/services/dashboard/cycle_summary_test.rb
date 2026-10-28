# frozen_string_literal: true

require "test_helper"

class Dashboard::CycleSummaryTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = User.create!(name: "Test User", email: "cycle_summary_test@example.com", password: "password123")
    @category = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
    @other_category = Category.create!(name: "Compras", is_default: true, category_type: "expense")
    @income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    @money_source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 100_000_000)
    @span = Date.new(2026, 10, 1)..Date.new(2026, 10, 31)
    @previous_span = Date.new(2026, 9, 1)..Date.new(2026, 9, 30)
  end

  def summary
    Dashboard::CycleSummary.new(user: @user, span: @span, previous_span: @previous_span).call
  end

  def create_expense(amount:, date:, category: @category)
    Expense.create!(user: @user, category: category, amount: amount, date: date, description: "Gasto",
                    money_source: @money_source)
  end

  test "reports income, expense and net totals for the span" do
    Income.create!(user: @user, category: @income_category, amount: 12_450_000, date: Date.new(2026, 10, 5), description: "Salario", money_source: @money_source)
    create_expense(amount: 869_396, date: Date.new(2026, 10, 6))

    result = summary

    assert_in_delta 12_450_000, result[:income_total], 0.01
    assert_in_delta 869_396, result[:expense_total], 0.01
    assert_in_delta 12_450_000 - 869_396, result[:net_total], 0.01
  end

  test "expense count includes every transaction of the span" do
    3.times { |i| create_expense(amount: 10_000, date: Date.new(2026, 10, i + 1)) }

    assert_equal 3, summary[:expense_count]
  end

  test "deltas compare against the previous span using absolute values" do
Income.create!(user: @user, category: @income_category, amount: 10_000_000, date: Date.new(2026, 9, 5), description: "Salario", money_source: @money_source)
    create_expense(amount: 1_000_000, date: Date.new(2026, 9, 10))
    Income.create!(user: @user, category: @income_category, amount: 12_450_000, date: Date.new(2026, 10, 5), description: "Salario", money_source: @money_source)
    create_expense(amount: 869_396, date: Date.new(2026, 10, 6))

    result = summary

    assert_in_delta -13.06, result[:expense_delta_pct], 0.05
    net_current = 12_450_000 - 869_396
    net_previous = 10_000_000 - 1_000_000
    assert_in_delta((net_current - net_previous).to_f / net_previous * 100, result[:net_delta_pct], 0.01)
  end

  test "deltas are nil when the previous span has no expenses" do
    create_expense(amount: 100_000, date: Date.new(2026, 10, 5))

    assert_nil summary[:expense_delta_pct]
  end

  test "income delta compares income against the previous span" do
Income.create!(user: @user, category: @income_category, amount: 10_000_000, date: Date.new(2026, 9, 5), description: "Salario", money_source: @money_source)
    Income.create!(user: @user, category: @income_category, amount: 12_450_000, date: Date.new(2026, 10, 5), description: "Salario", money_source: @money_source)

    assert_in_delta 24.5, summary[:income_delta_pct], 0.01
  end

  test "income delta is nil when the previous span had no income" do
    Income.create!(user: @user, category: @income_category, amount: 12_450_000, date: Date.new(2026, 10, 5), description: "Salario", money_source: @money_source)

    assert_nil summary[:income_delta_pct]
  end

  test "evolution is a zero-filled daily series covering the whole span" do
    create_expense(amount: 220_000, date: Date.new(2026, 10, 5))
    Income.create!(user: @user, category: @income_category, amount: 1_000_000, date: Date.new(2026, 10, 5), description: "Salario", money_source: @money_source)

    result = summary

    assert_equal 31, result[:evolution].size
    assert_equal [ Date.new(2026, 10, 1), 0, 0 ], [ result[:evolution].first[:date], result[:evolution].first[:income], result[:evolution].first[:expense] ]
    day5 = result[:evolution][4]
    assert_equal 1_000_000, day5[:income]
    assert_equal 220_000, day5[:expense]
  end

  test "top_categories ranks by amount with percentage of the total" do
    create_expense(amount: 520_000, date: Date.new(2026, 10, 2), category: @category)
    create_expense(amount: 298_000, date: Date.new(2026, 10, 3), category: @other_category)

    result = summary

    assert_equal [ "Transporte", "Compras" ], result[:top_categories].map { |c| c[:name] }
    assert_in_delta 520_000, result[:top_categories].first[:total], 0.01
    assert_in_delta 63.6, result[:top_categories].first[:percentage], 0.01
  end

  test "cycle progress counts days elapsed within the span" do
    travel_to Date.new(2026, 10, 18) do
      result = summary
      assert_equal 18, result[:days_elapsed]
      assert_equal 31, result[:days_total]
      assert_equal 58, result[:period_progress_pct].round
    end
  end

  test "projected spend extrapolates the daily rate to the whole span" do
    create_expense(amount: 1_800_000, date: Date.new(2026, 10, 6))

    travel_to Date.new(2026, 10, 18) do
      result = summary
      projected = 1_800_000 * 31 / 18.0
      assert_in_delta projected, result[:projected_spend], 0.01
    end
  end

  test "projected spend returns nil until enough cycle days have elapsed" do
    create_expense(amount: 1_800_000, date: Date.new(2026, 10, 2))

    travel_to Date.new(2026, 10, 4) do
      result = summary
      assert_nil result[:projected_spend]
      assert_nil result[:on_track]
    end
  end

  test "projected spend is available once the minimum elapsed days are reached" do
    create_expense(amount: 1_800_000, date: Date.new(2026, 10, 3))

    travel_to Date.new(2026, 10, 5) do
      result = summary
      assert_in_delta 1_800_000 * 31 / 5.0, result[:projected_spend], 0.01
    end
  end

  test "uses recurring commitments from day one when there are enough expense templates" do
    3.times do |i|
      template = @user.recurring_templates.create!(kind: "expense", amount: 1_000_000, category: @category,
                                                   description: "Fijo #{i}", frequency: "monthly",
                                                   payment_day: i * 3 + 1, source: "manual", active: true)
      next if i == 2

      Expense.create!(user: @user, category: @category, amount: 1_000_000, date: Date.new(2026, 10, i * 3 + 2),
                      description: template.description, money_source: @money_source, recurring_template: template)
    end
    create_expense(amount: 300_000, date: Date.new(2026, 10, 2))

    travel_to Date.new(2026, 10, 3) do
      result = summary

      # 3 templates are enough to switch modes; 2 are fully paid and not added
      # again, the unpaid one contributes its full amount. Variable spend still
      # gets its daily rate (300_000 over 3 elapsed days × remaining 28 days).
      assert_equal :recurring, result[:projection_basis]
      projected = 2_300_000 + 1_000_000 + (300_000 / 3.to_d) * 28
      assert_in_delta projected, result[:projected_spend], 0.01
    end
  end

  test "partially paid template only counts its remaining balance" do
    template = nil
    3.times do |i|
      template = @user.recurring_templates.create!(kind: "expense", amount: 1_000_000, category: @category,
                                                   description: "Fijo #{i}", frequency: "monthly",
                                                   payment_day: i * 3 + 1, source: "manual", active: true)
      if i == 2
        Expense.create!(user: @user, category: @category, amount: 400_000, date: Date.new(2026, 10, 8),
                        description: "Pago parcial", money_source: @money_source, recurring_template: template)
      end
    end
    create_expense(amount: 100_000, date: Date.new(2026, 10, 2))

    travel_to Date.new(2026, 10, 8) do
      result = summary

      # Spent: 500_000 (400_000 partial + 100_000 variable). Unpaid fixed:
      # 1_000_000 + 1_000_000 + 600_000. Variable rate: 100_000 / 8 × 23 days.
      projected = 500_000 + 2_600_000 + (100_000 / 8.to_d) * 23
      assert_in_delta projected, result[:projected_spend], 0.01
      assert_equal :recurring, result[:projection_basis]
    end
  end

  test "inactive templates do not feed the recurring projection" do
    3.times do |i|
      @user.recurring_templates.create!(kind: "expense", amount: 1_000_000, category: @category,
                                        description: "Fijo #{i}", frequency: "monthly", payment_day: i * 3 + 1,
                                        source: "manual", active: i != 2)
    end
    create_expense(amount: 250_000, date: Date.new(2026, 10, 2))

    travel_to Date.new(2026, 10, 3) do
      result = summary

      # Only 2 active templates: back to the daily-rate mode with its minimum days.
      assert_equal :daily, result[:projection_basis]
      assert_nil result[:projected_spend]
    end
  end

  test "recurring basis with no elapsed days still projects nothing" do
    3.times do |i|
      @user.recurring_templates.create!(kind: "expense", amount: 1_000_000, category: @category,
                                        description: "Fijo #{i}", frequency: "monthly", payment_day: i * 3 + 1,
                                        source: "manual", active: true)
    end

    travel_to Date.new(2026, 9, 30) do
      result = summary
      assert_nil result[:projected_spend]
    end
  end

  test "is on track when the projected spend stays under the income" do
    Income.create!(user: @user, category: @income_category, amount: 12_450_000, date: Date.new(2026, 10, 5), description: "Salario", money_source: @money_source)
    create_expense(amount: 1_800_000, date: Date.new(2026, 10, 6))

    travel_to Date.new(2026, 10, 18) do
      assert_equal true, summary[:on_track]
    end
  end

  test "is over the meta when the projected spend exceeds the income" do
    Income.create!(user: @user, category: @income_category, amount: 500_000, date: Date.new(2026, 10, 5), description: "Salario", money_source: @money_source)
    create_expense(amount: 900_000, date: Date.new(2026, 10, 6))

    travel_to Date.new(2026, 10, 18) do
      assert_equal false, summary[:on_track]
    end
  end

  test "upcoming payments lists active expense templates due within 10 days" do
    soon = @user.recurring_templates.create!(kind: "expense", amount: 820_000, category: @category, description: "Tarjeta de crédito",
                                             frequency: "monthly", payment_day: (Date.current + 3).day, source: "manual", active: true)
    @user.recurring_templates.create!(kind: "expense", amount: 2_818_000, category: @other_category, description: "Carro",
                                      frequency: "monthly", payment_day: (Date.current + 20).day, source: "manual", active: true)
    @user.recurring_templates.create!(kind: "income", amount: 1_000_000, category: @other_category, description: "Salario",
                                      frequency: "monthly", payment_day: (Date.current + 3).day, source: "manual", active: true)
    @user.recurring_templates.create!(kind: "expense", amount: 999, category: @other_category, description: "Inactivo",
                                      frequency: "monthly", payment_day: (Date.current + 3).day, source: "manual", active: false)

    result = summary

    assert_equal [ soon.id ], result[:upcoming_payments].map { |p| p[:template].id }
    assert_in_delta 820_000, result[:upcoming_payments].first[:amount], 0.01
    assert_equal Date.current + 3, result[:upcoming_payments].first[:next_date]
    assert_not result[:upcoming_payments].first[:paid]
  end

  test "upcoming payments includes cycle payments already made" do
    template = @user.recurring_templates.create!(kind: "expense", amount: 500_000, category: @category, description: "Servicio",
                                                frequency: "monthly", payment_day: 24, source: "manual", active: true)
    Expense.create!(user: @user, category: @category, amount: 500_000, date: Date.new(2026, 10, 24),
                    description: "Servicio", money_source: @money_source, recurring_template_id: template.id)

    result = summary

    payment = result[:upcoming_payments].find { |item| item[:template].id == template.id }
    assert payment
    assert_equal Date.new(2026, 10, 24), payment[:next_date]
    assert payment[:paid]
  end

  test "next_occurrence_date clamps payment days beyond the month end" do
    assert_equal Date.new(2026, 2, 28), Dashboard::CycleSummary.next_occurrence_date(31, from: Date.new(2026, 2, 1))
    assert_equal Date.new(2026, 4, 5), Dashboard::CycleSummary.next_occurrence_date(5, from: Date.new(2026, 3, 30))
    assert_equal Date.new(2026, 3, 15), Dashboard::CycleSummary.next_occurrence_date(15, from: Date.new(2026, 3, 15))
  end
end
