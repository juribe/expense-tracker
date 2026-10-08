# frozen_string_literal: true

require "test_helper"

# Credits::Simulator rebuilds the amortization schedule with extra principal
# payments (one-time, recurring or target-payoff search) and returns the
# comparison numbers. All results come from the schedule engine.
#
# Reference loan: balance $1,200 · installment $300 · monthly rate 1% →
# baseline: 5 installments, interest $30.91, payoff 2026-05-05.
class SimulatorTest < ActiveSupport::TestCase
  setup do
    projection = build_projection
    @projection = projection
  end

  test "one-time extra payment reduces term and saves interest" do
    results = Credits::Simulator.run(projection: @projection, kind: "one_time_extra",
                                     params: { "amount" => "300.00", "after_period" => 2 })

    assert_equal 4, results["installments"]
    assert_equal 1, results["installments_eliminated"]
    assert_equal "2026-04-05", results["payoff_date"]
    assert_equal BigDecimal("24.57"), results["future_interest"].to_d
    assert_equal BigDecimal("30.91"), results["baseline_interest"].to_d
    assert_equal BigDecimal("6.34"), results["interest_saved"].to_d
    assert_equal BigDecimal("300.00"), results["extra_cash"].to_d
  end

  test "one-time extra payment also reports the reduce-installment alternative" do
    results = Credits::Simulator.run(projection: @projection, kind: "one_time_extra",
                                     params: { "amount" => "300.00", "after_period" => 2 })

    alternative = results["reduce_installment"]
    assert alternative.present?
    # Total term kept: 2 periods at the full installment (extra applied at 2)
    # plus 3 recalculated periods for the reduced balance $321.12.
    assert_equal 5, alternative["installments"]
    assert_equal 0, alternative["installments_eliminated"]
    assert_equal "2026-05-05", alternative["payoff_date"]
    # Annuity installment for $321.12 at 1% over 3 periods ≈ 109.19.
    assert_in_delta 109.19, alternative["new_installment_amount"].to_f, 0.02
    assert_in_delta BigDecimal("30.91") - alternative["future_interest"].to_d,
                    alternative["interest_saved"].to_d, 0.01
  end

  test "recurring extra payment every period" do
    results = Credits::Simulator.run(projection: @projection, kind: "recurring_extra",
                                     params: { "amount" => "100.00", "every_n_periods" => 1 })

    assert_equal 4, results["installments"]
    assert_equal 1, results["installments_eliminated"]
    assert_equal BigDecimal("24.56"), results["future_interest"].to_d
    assert_equal BigDecimal("6.35"), results["interest_saved"].to_d
    assert_equal BigDecimal("300.00"), results["extra_cash"].to_d
    assert_nil results["reduce_installment"]
  end

  test "recurring extra payment every three periods" do
    results = Credits::Simulator.run(projection: @projection, kind: "recurring_extra",
                                     params: { "amount" => "300.00", "every_n_periods" => 3 })

    assert_equal 4, results["installments"]
    assert_equal BigDecimal("21.51"), results["future_interest"].to_d
    assert_equal BigDecimal("9.40"), results["interest_saved"].to_d
    assert_equal BigDecimal("300.00"), results["extra_cash"].to_d
  end

  test "target payoff finds the required recurring extra via search" do
    results = Credits::Simulator.run(projection: @projection, kind: "target_payoff",
                                     params: { "months_earlier" => 2 })

    assert_equal 3, results["installments"]
    assert_equal 2, results["installments_eliminated"]
    assert results["required_extra"].to_d.positive?
    assert_equal (BigDecimal("300") + results["required_extra"].to_d), results["new_total_payment"].to_d
    assert_equal BigDecimal("30.91"), results["baseline_interest"].to_d
    assert results["interest_saved"].to_d.positive?
  end

  test "target payoff capped at paying off immediately" do
    results = Credits::Simulator.run(projection: @projection, kind: "target_payoff",
                                     params: { "months_earlier" => 99 })

    assert_equal 1, results["installments"]
    assert_equal 4, results["installments_eliminated"]
    assert_equal BigDecimal("912.00"), results["required_extra"].to_d
  end

  test "simulated schedule matches a directly built schedule with the found extra" do
    results = Credits::Simulator.run(projection: @projection, kind: "target_payoff",
                                     params: { "months_earlier" => 2 })

    rebuilt = Credits::Amortization::ScheduleBuilder.build(
      **base_schedule_options,
      extras: { recurring: { start_period: 1, every_n_periods: 1, amount: results["required_extra"].to_d } }
    )

    assert_equal results["installments"], rebuilt.installments
    assert_equal results["future_interest"].to_d, rebuilt.future_interest
  end

  private

  def build_projection
    source = MoneySource.create!(user: User.create!(name: "Sim User", email: "sim@example.com",
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
        "latest_insurance" => "0.0", "latest_other" => "0.0",
        "actual_payments_count" => 0, "user_supplied" => [],
        "periodic_rate" => "0.01", "next_payment_date" => "2026-01-05",
        "start_installment_number" => 1, "engine" => "fixed_installment"
      },
      assumptions: []
    )
    # Build the schedule through the engine so the projection mirrors production.
    result = Credits::Amortization::ScheduleBuilder.build(**base_schedule_options)
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
