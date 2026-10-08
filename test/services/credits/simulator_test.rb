# frozen_string_literal: true

require "test_helper"

# Credits::Simulator runs the Colombian extra-payment strategies against a
# credit projection's schedule: reduce_term (cuota fija, plazo baja),
# reduce_installment (plazo fijo, cuota se recalcula), prepay_installments
# (adelanto de cuotas a valor facial — NO reduce capital) and target_payoff
# (cuánto extra para terminar N antes). Todos los resultados salgan del
# motor de amortización.
#
# Reference loan: balance $1,200 · installment $300 · monthly rate 1% →
# baseline: 5 installments, interest $30.91, payoff 2026-05-05.
class SimulatorTest < ActiveSupport::TestCase
  setup do
    @projection = build_projection
    @projection_with_charges = build_projection(insurance: "10.0", other: "2.0")
  end

  # ------------------------------------------------------- reduce_term
  test "reduce_term keeps the installment and shortens the term" do
    results = run_strategy("reduce_term", { "amount" => "300.00", "after_period" => 2 })

    assert_equal "reduce_term", results["strategy"]
    assert_equal 4, results["installments"]
    assert_equal 1, results["installments_eliminated"]
    assert_equal "2026-04-05", results["payoff_date"]
    assert_equal BigDecimal("24.57"), results["future_interest"].to_d
    assert_equal BigDecimal("30.91"), results["baseline_interest"].to_d
    assert_equal BigDecimal("6.34"), results["interest_saved"].to_d
    assert_equal BigDecimal("300.00"), results["extra_cash"].to_d
    # Same contractual installment — only the term moves.
    assert_equal BigDecimal("300.00"), results["new_installment"].to_d
    assert_equal BigDecimal("1200"), results["balance_before"].to_d
    assert_equal BigDecimal("900"), results["balance_after"].to_d
  end

  test "reduce_term with repeat_every applies the amount every N periods" do
    results = run_strategy("reduce_term", { "amount" => "100.00", "repeat_every" => 1 })

    assert_equal 4, results["installments"]
    assert_equal BigDecimal("24.56"), results["future_interest"].to_d
    assert_equal BigDecimal("6.35"), results["interest_saved"].to_d
    assert_equal BigDecimal("300.00"), results["extra_cash"].to_d
  end

  test "reduce_term repeating every three periods" do
    results = run_strategy("reduce_term", { "amount" => "300.00", "repeat_every" => 3 })

    assert_equal 4, results["installments"]
    assert_equal BigDecimal("21.51"), results["future_interest"].to_d
    assert_equal BigDecimal("9.40"), results["interest_saved"].to_d
    assert_equal BigDecimal("300.00"), results["extra_cash"].to_d
  end

  test "legacy one_time_extra and recurring_extra map to reduce_term" do
    legacy_once = Credits::Simulator.run(projection: @projection, strategy: "one_time_extra",
                                         params: { "amount" => "300.00", "after_period" => 2 })
    legacy_recurring = Credits::Simulator.run(projection: @projection, strategy: "recurring_extra",
                                              params: { "amount" => "100.00" })

    assert_equal "reduce_term", legacy_once["strategy"]
    assert_equal BigDecimal("6.34"), legacy_once["interest_saved"].to_d
    assert_equal "reduce_term", legacy_recurring["strategy"]
    assert_equal BigDecimal("24.56"), legacy_recurring["future_interest"].to_d
  end

  # -------------------------------------------------- reduce_installment
  test "reduce_installment keeps the term and recalculates the installment" do
    results = run_strategy("reduce_installment", { "amount" => "300.00", "after_period" => 2 })

    assert_equal "reduce_installment", results["strategy"]
    # Total term preserved: 2 periods at the full installment + 3 recalculated.
    assert_equal 5, results["installments"]
    assert_equal 0, results["installments_eliminated"]
    assert_equal "2026-05-05", results["payoff_date"]
    # Annuity for $321.12 at 1% over 3 periods ≈ 109.19.
    assert_in_delta 109.19, results["new_installment"].to_f, 0.02
    assert_in_delta 300.00 - 109.19, results["reduction"].to_f, 0.02
    # Term kept → less interest saved than reduce_term with the same amount.
    reduce_term = run_strategy("reduce_term", { "amount" => "300.00", "after_period" => 2 })
    assert_operator results["interest_saved"].to_d, :<, reduce_term["interest_saved"].to_d
    assert results["interest_saved"].to_d.positive?
  end

  test "reduce_installment keeps insurance and other charges intact" do
    results = Credits::Simulator.run(projection: @projection_with_charges, strategy: "reduce_installment",
                                     params: { "amount" => "300.00", "after_period" => 2 })

    # Balance after 2 periods at $300 with $12 of charges: 1,200 − 276 − 278.76
    # − extra 300 = 345.24. Annuity over 3 periods ≈ 117.39 PLUS the untouched
    # insurance and other charges (10 + 2) — never recomputed downward.
    assert_equal BigDecimal("1200"), results["balance_before"].to_d
    assert_in_delta 129.39, results["new_installment"].to_f, 0.02
    annuity = results["new_installment"].to_d - BigDecimal("12")
    assert_in_delta 117.39, annuity.to_f, 0.02
    assert_equal "0.0", results["insurance_impact"]
    assert_equal "0.0", results["other_impact"]
  end

  # -------------------------------------------------- prepay_installments
  test "prepay_installments covers future installments without touching capital" do
    results = run_strategy("prepay_installments", { "amount" => "500.00" })

    assert_equal "prepay_installments", results["strategy"]
    assert_equal 1, results["installments_covered"]
    assert_equal 1, results["months_without_payment"]
    assert results["partial_installment"]
    # The schedule does not change: no interest savings, same payoff date.
    assert_equal BigDecimal("0"), results["interest_saved"].to_d
    assert_equal 5, results["installments"]
    assert_equal "2026-05-05", results["payoff_date"]
    assert_equal BigDecimal("1200"), results["balance_after"].to_d
    assert_equal BigDecimal("500.00"), results["freed_cash"].to_d
  end

  test "prepay_installments covers whole installments at face value" do
    results = run_strategy("prepay_installments", { "amount" => "900.00" })

    assert_equal 3, results["installments_covered"]
    assert_equal 3, results["months_without_payment"]
    assert_not results["partial_installment"]
    assert_equal BigDecimal("900.00"), results["freed_cash"].to_d
    assert_equal BigDecimal("0"), results["installments_eliminated"].to_d
  end

  # ------------------------------------------------------- target_payoff
  test "target payoff finds the required recurring extra via search" do
    results = run_strategy("target_payoff", { "months_earlier" => 2 })

    assert_equal "target_payoff", results["strategy"]
    assert_equal 3, results["installments"]
    assert_equal 2, results["installments_eliminated"]
    assert results["required_extra"].to_d.positive?
    assert_equal (BigDecimal("300") + results["required_extra"].to_d), results["new_total_payment"].to_d
    assert_equal BigDecimal("30.91"), results["baseline_interest"].to_d
    assert results["interest_saved"].to_d.positive?
  end

  test "target payoff capped at paying off immediately" do
    results = run_strategy("target_payoff", { "months_earlier" => 99 })

    assert_equal 1, results["installments"]
    assert_equal 4, results["installments_eliminated"]
    assert_equal BigDecimal("912.00"), results["required_extra"].to_d
  end

  test "simulated schedule matches a directly built schedule with the found extra" do
    results = run_strategy("target_payoff", { "months_earlier" => 2 })

    rebuilt = Credits::Amortization::ScheduleBuilder.build(
      **base_schedule_options,
      extras: { recurring: { start_period: 1, every_n_periods: 1, amount: results["required_extra"].to_d } }
    )

    assert_equal results["installments"], rebuilt.installments
    assert_equal results["future_interest"].to_d, rebuilt.future_interest
  end

  test "every strategy reports the current block for comparison" do
    %w[reduce_term reduce_installment prepay_installments target_payoff].each do |strategy|
      params = strategy == "target_payoff" ? { "months_earlier" => 1 } : { "amount" => "300.00" }
      results = run_strategy(strategy, params)

      current = results["current"]
      assert_equal 5, current["remaining_installments"]
      assert_equal BigDecimal("300.00"), current["installment"].to_d
      assert_equal BigDecimal("30.91"), current["future_interest"].to_d
      assert_equal "2026-05-05", current["payoff_date"]
    end
  end

  private

  def run_strategy(strategy, params)
    Credits::Simulator.run(projection: @projection, strategy: strategy, params: params)
  end

  def build_projection(insurance: nil, other: nil)
    source = MoneySource.create!(user: User.create!(name: "Sim User #{insurance}#{other}#{Time.current.to_i}",
                                                    email: "sim#{rand(10_000)}@example.com",
                                                    password: "password123"),
                                 name: "Ref Loan", kind: "loan", sub_kind: "personal")
    source.create_credit_account!(
      outstanding_balance: 1_200, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    projection = source.build_credit_projection
    projection.assign_attributes(
      estimated: false, fingerprint: "test", computed_at: Time.current,
      inputs: {
        "balance" => "1200.0", "interest_rate" => "1.0", "interest_rate_type" => "monthly",
        "payment_frequency" => "monthly", "installment_amount" => "300.0",
        "installment_count" => 5, "installments_paid" => 0, "start_date" => "2026-01-05",
        "current_installment_number" => 0, "latest_payment_date" => nil,
        "latest_principal" => "0.0", "latest_interest" => "0.0",
        "latest_insurance" => insurance || "0.0", "latest_other" => other || "0.0",
        "actual_payments_count" => 0, "user_supplied" => [],
        "periodic_rate" => "0.01", "next_payment_date" => "2026-01-05",
        "start_installment_number" => 1, "engine" => "fixed_installment"
      },
      assumptions: []
    )
    result = Credits::Amortization::ScheduleBuilder.build(
      **base_schedule_options.merge(insurance: (insurance || "0").to_d, other: (other || "0").to_d)
    )
    projection.schedule = { "future" => result.rows.map { |row| marshal_row(row) } }
    projection.summary = {
      "future_interest" => result.future_interest.to_s, "remaining_installments" => result.installments
    }
    projection.save!
    projection
  end

  def base_schedule_options
    {
      balance: BigDecimal("1200"),
      periodic_rate: BigDecimal("0.01"),
      installment_amount: BigDecimal("300"),
      insurance: 0.to_d,
      other: 0.to_d,
      start_installment_number: 1,
      first_payment_date: Date.new(2026, 1, 5),
      frequency: "monthly"
    }
  end

  def marshal_row(row)
    { "installment_number" => row.installment_number, "date" => row.date.iso8601,
      "opening_balance" => row.opening_balance.to_s("F"), "principal" => row.principal.to_s("F"),
      "interest" => row.interest.to_s("F"), "insurance" => row.insurance.to_s("F"),
      "other" => row.other.to_s("F"), "total_payment" => row.total_payment.to_s("F"),
      "closing_balance" => row.closing_balance.to_s("F") }
  end
end
