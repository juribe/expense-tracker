# frozen_string_literal: true

require "test_helper"

# Credits::Comparison builds the scenario table (baseline + up to 3 saved
# scenarios) and ranks the best strategy per objective.
class ComparisonTest < ActiveSupport::TestCase
  setup do
    @loan = MoneySource.create!(
      user: User.create!(name: "Cmp User", email: "cmp@example.com", password: "password123"),
      name: "Ref Loan", kind: "loan", sub_kind: "personal"
    )
    @loan.create_credit_account!(
      outstanding_balance: 1_200, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    @projection = Credits::Projection::Builder.call(money_source: @loan).result
  end

  test "comparison rows include the baseline and saved scenarios" do
    create_scenario("recurring_extra", "+100/mes", { "amount" => "100" })
    create_scenario("one_time_extra", "+300 una vez", { "amount" => "300" })

    comparison = Credits::Comparison.call(projection: @projection)

    names = comparison.rows.map { |row| row["name"] }
    assert_equal "Cuota actual", names.first
    assert_includes names, "+100/mes"
    assert_includes names, "+300 una vez"

    baseline = comparison.rows.first
    assert_equal 5, baseline["installments"]
    assert_equal BigDecimal("30.91"), baseline["future_interest"].to_d
    assert_equal 0, baseline["interest_saved"].to_d
  end

  test "rows sort by interest saved descending" do
    create_scenario("recurring_extra", "+100/mes", { "amount" => "100" })
    create_scenario("one_time_extra", "+300 una vez", { "amount" => "300" })

    comparison = Credits::Comparison.call(projection: @projection)
    savings = comparison.rows.drop(1).map { |row| row["interest_saved"].to_d }

    assert_equal savings.sort.reverse, savings
    assert savings.first.positive?
  end

  test "best strategy by each objective" do
    small = create_scenario("recurring_extra", "+100/mes", { "amount" => "100" })
    big = create_scenario("one_time_extra", "+500 una vez", { "amount" => "500" })

    recurring_big = create_scenario("recurring_extra", "+500/mes", { "amount" => "500" })
    max_savings = Credits::Comparison.call(projection: @projection, objective: "max_savings")
    fastest = Credits::Comparison.call(projection: @projection, objective: "fastest_payoff")
    min_payment = Credits::Comparison.call(projection: @projection, objective: "min_payment")
    balanced = Credits::Comparison.call(projection: @projection, objective: "balanced")

    # +$500/month saves the most interest ($14.79) and ends in February.
    assert_equal recurring_big.name, max_savings.best["name"]
    assert_equal recurring_big.name, fastest.best["name"]
    # The one-time extra + recalculated installment carries the lowest payment.
    assert_equal big.name, min_payment.best["name"]
    # +$500 once saves $13.63 with only $500 of extra cash — the best ratio.
    assert_equal big.name, balanced.best["name"]
  end

  test "max_savings ranks the target payoff scenario by its interest saved" do
    create_scenario("target_payoff", "Terminar 3 antes", { "months_earlier" => 3 })
    create_scenario("one_time_extra", "+300 una vez", { "amount" => "300" })

    comparison = Credits::Comparison.call(projection: @projection, objective: "max_savings")

    assert_equal "Terminar 3 antes", comparison.best["name"]
  end

  test "an empty scenario list only shows the baseline with no best" do
    comparison = Credits::Comparison.call(projection: @projection)

    assert_equal 1, comparison.rows.size
    assert_nil comparison.best
  end

  private

  def create_scenario(kind, name, params)
    @loan.reload
    result = Credits::Scenarios::Create.call(money_source: @loan, kind: kind, name: name, params: params)
    assert result.success?, result.errors.inspect
    result.result
  end
end
