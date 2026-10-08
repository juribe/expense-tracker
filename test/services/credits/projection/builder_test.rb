# frozen_string_literal: true

require "test_helper"

# Credits::Projection::Builder compiles and persists the loan's financial
# projection (schedule + summary + assumptions) from collected inputs.
# It never writes to the credit tables; missing data makes the projection
# estimated, and a real payment far from the projected row flags review.
#
# Reference loan (all multiples of the ScheduleBuilder reference):
#   original principal $1,500,000 · 5 installments · monthly rate 1%
#   installment $300,000 · ledger: 15/285 · 12.15/287.85 · 9.27/290.73 ...
class ProjectionBuilderTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Projection User", email: "projection@example.com", password: "password123")
    @loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    travel_to Date.new(2026, 2, 1)
  end

  teardown do
    travel_back
  end

  test "builds a projection from credit data and real payments" do
    @loan.create_credit_account!(
      principal_amount: 1_500_000, outstanding_balance: 1_500_000,
      interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    create_payment(Date.new(2026, 1, 5), principal: 285_000, interest: 15_000)

    projection = Credits::Projection::Builder.call(money_source: @loan).result

    assert_not projection.estimated?
    rows = projection.future_rows
    assert_equal 5, rows.size

    first = rows.first
    assert_equal 2, first["installment_number"]
    assert_equal BigDecimal("1215000"), first["opening_balance"].to_d
    assert_equal BigDecimal("12150"), first["interest"].to_d
    assert_equal BigDecimal("287850"), first["principal"].to_d

    summary = projection.summary
    assert_equal 1, summary["actual_payments_count"]
    assert_equal 5, summary["remaining_installments"]
    assert_equal "2026-02-05", summary["next_payment_date"]
    assert_equal "2026-06-05", summary["payoff_date"]
    assert_equal BigDecimal("15000"), summary["past_interest"].to_d
    assert_equal BigDecimal("285000"), summary["past_principal"].to_d
    assert_equal BigDecimal("31675.72"), summary["future_interest"].to_d
    assert_equal BigDecimal("1215000"), summary["future_principal"].to_d
    assert_not summary["needs_review"]
  end

  test "user-entered data produces an estimated projection with assumptions" do
    @loan.create_credit_account!(outstanding_balance: 1_500_000, payment_frequency: "monthly")

    result = Credits::Projection::Builder.call(
      money_source: @loan,
      overrides: {
        "interest_rate" => "21.27", "interest_rate_type" => "effective_annual",
        "installment_amount" => "300000", "current_installment_number" => "12",
        "latest_payment_date" => "2026-02-05",
        "principal_amount" => "285000", "interest_amount" => "15000",
        "insurance_amount" => "10000", "other_amount" => "0"
      }
    )

    assert result.success?
    projection = result.result
    assert projection.estimated?
    assumptions = projection.assumptions.join(" ")
    assert_match(/21\.27/, assumptions)
    assert_match(/10\.000/, assumptions)
    assert_match(/estimad/i, assumptions)
  end

  test "fails with clear errors when critical data is missing" do
    @loan.create_credit_account!(payment_frequency: "monthly")

    result = Credits::Projection::Builder.call(money_source: @loan)

    assert result.failure?
    joined = result.errors.join(" ")
    assert_includes joined, "saldo"
    assert_includes joined, "cuota"
    assert_includes joined, "tasa"
  end

  test "a real payment far from the projected row flags the credit for review" do
    @loan.create_credit_account!(
      principal_amount: 1_500_000, outstanding_balance: 1_500_000,
      interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    create_payment(Date.new(2026, 1, 5), principal: 285_000, interest: 15_000)
    create_payment(Date.new(2026, 2, 5), principal: 287_850, interest: 12_150)
    # Payment 3 diverges: interest 50k vs the projected 9.27k for installment 3.
    create_payment(Date.new(2026, 3, 5), principal: 290_730, interest: 50_000)

    projection = Credits::Projection::Builder.call(money_source: @loan).result

    assert projection.summary["needs_review"]
    deviations = projection.deviations
    assert deviations.any? { |d| d["installment_number"] == 3 && d["field"] == "interest" }
  end

  test "a real payment close to the projected row does not flag review" do
    @loan.create_credit_account!(
      principal_amount: 1_500_000, outstanding_balance: 1_500_000,
      interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    create_payment(Date.new(2026, 1, 5), principal: 285_000, interest: 15_000)
    create_payment(Date.new(2026, 2, 5), principal: 287_900, interest: 12_100)

    projection = Credits::Projection::Builder.call(money_source: @loan).result

    assert_not projection.summary["needs_review"]
    assert_empty projection.deviations
  end

  test "an existing projection becomes stale when a new payment is recorded" do
    @loan.create_credit_account!(
      outstanding_balance: 1_500_000, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    create_payment(Date.new(2026, 1, 5), principal: 285_000, interest: 15_000)

    projection = Credits::Projection::Builder.call(money_source: @loan).result
    assert_not projection.stale?

    create_payment(Date.new(2026, 2, 5), principal: 287_850, interest: 12_150)

    assert projection.stale?
  end

  test "rebuilding recomputes persisted scenario results" do
    @loan.create_credit_account!(
      outstanding_balance: 1_200_000, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )

    Credits::Projection::Builder.call(money_source: @loan)
    scenario = Credits::Scenarios::Create.call(
      money_source: @loan, kind: "reduce_term", name: "+100 mil/mes",
      params: { "amount" => "100000", "repeat_every" => 1 }
    ).result
    assert scenario.results["interest_saved"].to_d.positive?

    # Force staleness, then rebuild: scenario numbers must track the new baseline.
    scenario.update!(results: { "interest_saved" => "0" })

    Credits::Projection::Builder.call(money_source: @loan, force: true)

    assert_not_equal 0, scenario.reload.results["interest_saved"].to_d
  end

  private

  def create_payment(date, principal: 0, interest: 0, insurance: 0, other: 0)
    total = principal + interest + insurance + other
    expense = Expense.create!(
      user: @user, amount: total, description: "Cuota hipoteca", date: date,
      kind: "expense", source: "manual", money_source: @loan
    )
    Payment.create!(
      user: @user, expense: expense, money_source: @loan, date: date, amount: total,
      principal_amount: principal, interest_amount: interest,
      insurance_amount: insurance, other_amount: other
    )
  end
end
