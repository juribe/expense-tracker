# frozen_string_literal: true

require "test_helper"

# Credits::Comparison builds two view models over the simulator:
#   .call  — saved scenarios (baseline + up to 3) ranked per objective
#   .quick — transient metrics×strategies comparison for one amount
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

  # ------------------------------------------------------- saved scenarios
  test "comparison rows include the baseline and saved scenarios" do
    create_scenario("reduce_term", "+100/mes", { "amount" => "100", "repeat_every" => 1 })
    create_scenario("reduce_installment", "+300 a cuota", { "amount" => "300" })

    comparison = Credits::Comparison.call(projection: @projection)

    names = comparison.rows.map { |row| row["name"] }
    assert_equal "Cuota actual", names.first
    assert_includes names, "+100/mes"
    assert_includes names, "+300 a cuota"

    baseline = comparison.rows.first
    assert_equal 5, baseline["installments"]
    assert_equal BigDecimal("30.91"), baseline["future_interest"].to_d
    assert_equal 0, baseline["interest_saved"].to_d
  end

  test "rows sort by interest saved descending" do
    create_scenario("reduce_term", "+100/mes", { "amount" => "100", "repeat_every" => 1 })
    create_scenario("reduce_term", "+500/mes", { "amount" => "500", "repeat_every" => 1 })

    comparison = Credits::Comparison.call(projection: @projection)
    savings = comparison.rows.drop(1).map { |row| row["interest_saved"].to_d }

    assert_equal savings.sort.reverse, savings
    assert savings.first.positive?
  end

  test "best strategy by each objective" do
    small = create_scenario("reduce_term", "+100/mes", { "amount" => "100", "repeat_every" => 1 })
    recuring_big = create_scenario("reduce_term", "+1000/mes", { "amount" => "1000", "repeat_every" => 1 })
    lower = create_scenario("reduce_installment", "+500 a cuota", { "amount" => "500" })

    max_savings = Credits::Comparison.call(projection: @projection, objective: "max_savings")
    fastest = Credits::Comparison.call(projection: @projection, objective: "fastest_payoff")
    min_payment = Credits::Comparison.call(projection: @projection, objective: "min_payment")
    balanced = Credits::Comparison.call(projection: @projection, objective: "balanced")

    # +$1000/month saves the most interest ($18.91) and ends in February.
    assert_equal recuring_big.name, max_savings.best["name"]
    assert_equal recuring_big.name, fastest.best["name"]
    # The one-time extra with recalculated installment carries the lowest payment.
    assert_equal lower.name, min_payment.best["name"]
    # +$100/month is the best savings-per-extra-peso option.
    assert_equal small.name, balanced.best["name"]
  end

  test "the reduce_installment row shows the recalculated installment as payment" do
    scenario = create_scenario("reduce_installment", "+300 a cuota", { "amount" => "300" })

    comparison = Credits::Comparison.call(projection: @projection)
    row = comparison.rows.find { |r| r["scenario_id"] == scenario.id }

    # Term kept → lowest ongoing payment of all one-shot strategies.
    assert_operator row["payment"].to_d, :<, BigDecimal("300")
    assert_equal scenario.results["new_installment"].to_d, row["payment"].to_d
  end

  test "the prepay row keeps the installment and reports no interest savings" do
    scenario = create_scenario("prepay_installments", "+900 adelantadas", { "amount" => "900" })

    comparison = Credits::Comparison.call(projection: @projection)
    row = comparison.rows.find { |r| r["scenario_id"] == scenario.id }

    assert_equal BigDecimal("300"), row["payment"].to_d
    assert_equal 0, row["interest_saved"].to_d
    assert_equal 3, row["months_without_payment"]
    assert_equal 0, row["installments_eliminated"]
  end

  test "an empty scenario list only shows the baseline with no best" do
    comparison = Credits::Comparison.call(projection: @projection)

    assert_equal 1, comparison.rows.size
    assert_nil comparison.best
  end

  # ---------------------------------------------------------- quick compare
  test "quick compare simulates the current state plus each strategy" do
    quick = Credits::Comparison.quick(projection: @projection, amount: "300")

    assert_equal 3, quick.strategies.size
    assert_equal %w[reduce_term reduce_installment prepay_installments], quick.strategies.map { |r| r["strategy"] }

    baseline = quick.current
    assert_equal "Cuota actual", baseline["name"]
    assert_equal BigDecimal("300"), baseline["payment"].to_d

    reduce_term = quick.strategies.find { |r| r["strategy"] == "reduce_term" }
    assert_equal 4, reduce_term["installments"]
    assert_equal BigDecimal("300"), reduce_term["extra_cash"].to_d
    assert_equal BigDecimal("300"), reduce_term["payment"].to_d

    prepay = quick.strategies.find { |r| r["strategy"] == "prepay_installments" }
    assert_equal 1, prepay["months_without_payment"]
    assert_equal 0, prepay["interest_saved"].to_d
    assert_equal BigDecimal("300"), prepay["payment"].to_d

    # Nothing gets persisted by a quick comparison.
    assert_equal 0, @loan.reload.credit_scenarios.count
  end

  test "recurring quick compare simulates a constant extra every installment" do
    quick = Credits::Comparison.quick(projection: @projection, amount: "200", mode: "recurring")

    assert_equal "recurring", quick.mode
    strategies = quick.strategies
    assert_equal 1, strategies.size
    assert_equal %w[reduce_term], strategies.map { |r| r["strategy"] }

    reduce_term = strategies.find { |r| r["strategy"] == "reduce_term" }
    # $200 extra every period: ledger from the engine
    #   1: 12/288 → 912 − 200 = 712
    #   2: 7.12/292.88 → 419.12 − 200 = 219.12
    #   3: 2.19 final 219.12 (after the last installment no more extras apply)
    # 3 installments, interest 21.31.
    assert_equal 3, reduce_term["installments"]
    assert_equal 2, reduce_term["installments_eliminated"]
    assert_equal BigDecimal("21.31"), reduce_term["future_interest"].to_d
    # Extra cash actually needed: 2 × 200 (the credit ends before a 3rd).
    assert_equal BigDecimal("400.00"), reduce_term["extra_cash"].to_d
    # The ongoing payment carries the extra: cuota + extra each period.
    assert_equal BigDecimal("500"), reduce_term["payment"].to_d
    assert_equal 1, reduce_term["repeat_every"].to_i

    # Nothing gets persisted.
    assert_equal 0, @loan.reload.credit_scenarios.count
  end

  private

  def create_scenario(kind, name, params)
    @loan.reload
    result = Credits::Scenarios::Create.call(money_source: @loan, kind: kind, name: name, params: params)
    assert result.success?, result.errors.inspect
    result.result
  end
end

# Auto-generated scenario names format the amount in Colombian pesos.
class ScenarioNamesFormattingTest < ActiveSupport::TestCase
  setup do
    @loan = MoneySource.create!(
      user: User.create!(name: "Fmt User", email: "fmt@example.com", password: "password123"),
      name: "Ref Loan", kind: "loan", sub_kind: "personal"
    )
    @loan.create_credit_account!(
      outstanding_balance: 1_200, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    Credits::Projection::Builder.call(money_source: @loan).result
  end

  test "default scenario names format the amount" do
    result = Credits::Scenarios::Create.call(money_source: @loan, kind: "reduce_installment",
                                             params: { "amount" => "5000000" })

    assert result.success?
    assert_equal "+$5.000.000 para pagar menos cada mes", result.result.name
  end

  test "explicit names win over defaults" do
    result = Credits::Scenarios::Create.call(money_source: @loan, kind: "reduce_term",
                                             name: "Aguinaldo al crédito",
                                             params: { "amount" => "5000000" })

    assert result.success?
    assert_equal "Aguinaldo al crédito", result.result.name
  end
end
