# frozen_string_literal: true

require "test_helper"

# CreditsController: the credit intelligence dashboard (projection,
# simulators, scenarios, amortization table) for a user's debt sources.
# Informational only — no credit or payment tables are touched.
class CreditsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::Helpers::NumberHelper

  setup do
    @user = User.create!(name: "Test User", email: "credits_ctrl@example.com", password: "password123")
    sign_in @user
    @loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
  end

  test "show builds and renders the projection when the credit has enough data" do
    @loan.create_credit_account!(
      outstanding_balance: 1_200_000, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )

    get money_source_credits_path(@loan)

    assert_response :success
    assert @loan.reload.credit_projection.present?
    assert_match "Cuota actual", @response.body
  end

  test "show redirects to the reconstruction form when data is missing" do
    @loan.create_credit_account!(payment_frequency: "monthly")

    get money_source_credits_path(@loan)

    assert_redirected_to money_source_credit_reconstruct_path(@loan)
  end

  test "another user's loan is not visible" do
    other = User.create!(name: "Otro", email: "other-credits@example.com", password: "password123")
    foreign = other.money_sources.create!(name: "Ajeno", kind: "loan")

    get money_source_credits_path(foreign)

    assert_response :not_found
  end

  test "reconstruct renders the form prefilled from the credit" do
    @loan.create_credit_account!(
      outstanding_balance: 1_200_000, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 2,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )

    get money_source_credit_reconstruct_path(@loan)

    assert_response :success
    assert_match "300000", @response.body.delete(".")
  end

  test "build creates the projection from user-entered data and marks it estimated" do
    post money_source_credit_build_path(@loan), params: {
      balance: "1200000", interest_rate: "1.0", interest_rate_type: "monthly",
      installment_amount: "300000", current_installment_number: "2",
      latest_payment_date: "2026-02-05", principal_amount: "288000",
      interest_amount: "12000", insurance_amount: "0", other_amount: "0"
    }

    assert_redirected_to money_source_credits_path(@loan)
    projection = @loan.reload.credit_projection
    assert projection.present?
    assert projection.estimated?
  end

  test "build re-renders the form when critical data is missing" do
    post money_source_credit_build_path(@loan), params: { balance: "1200000" }

    assert_response :unprocessable_entity
    assert_match "tasa", @response.body
  end

  test "refresh recomputes a stale projection" do
    @loan.create_credit_account!(
      outstanding_balance: 1_200_000, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    @projection = Credits::Projection::Builder.call(money_source: @loan).result
    @projection.update_column(:fingerprint, "stale")

    post money_source_credit_refresh_path(@loan)

    assert_redirected_to money_source_credits_path(@loan)
    assert_not @loan.reload.credit_projection.stale?
  end

  test "creating a scenario stores its computed results" do
    create_projection

    post money_source_credit_scenarios_path(@loan), params: {
      kind: "reduce_term", name: "+100 mil/mes", amount: "100000", repeat_every: 1
    }

    assert_redirected_to money_source_credits_path(@loan)
    scenario = @loan.reload.credit_scenarios.last
    assert_equal "reduce_term", scenario.kind
    assert_equal 1, scenario.params["repeat_every"].to_i
    assert_equal "100000", scenario.params["amount"].to_s
    assert scenario.results["interest_saved"].present?
  end

  test "a fourth scenario is rejected with the limit message" do
    create_projection
    3.times { |i| create_scenario_record(i) }

    post money_source_credit_scenarios_path(@loan), params: {
      kind: "one_time_extra", amount: "100000"
    }

    assert_redirected_to money_source_credits_path(@loan, amount: "100000")
    assert_match I18n.t("errors.messages.scenario_limit"), flash[:alert]
    assert_equal 3, @loan.reload.credit_scenarios.count
  end

  test "destroy removes one scenario and frees a slot" do
    create_projection
    scenario = create_scenario_record(0)

    delete money_source_credit_scenario_path(@loan, scenario)

    assert_redirected_to money_source_credits_path(@loan)
    assert_equal 0, @loan.reload.credit_scenarios.count
  end

  test "show renders the amortization table views without re-routing" do
    create_projection

    get money_source_credits_path(@loan)

    assert_response :success
    assert_match "table-responsive", @response.body

    get money_source_credits_path(@loan, view: "actual")

    assert_response :success
    assert_match "Real vs proyectado", @response.body
  end

  test "show renders the quick strategy comparison for the entered amount" do
    create_projection

    get money_source_credits_path(@loan, amount: "900000")

    assert_response :success
    assert_match "Terminar antes", @response.body
    assert_match "Adelantar cuotas", @response.body
    assert_equal 0, @loan.reload.credit_scenarios.count
  end

  test "show supports the recurring (constant extra) quick comparison" do
    create_projection

    get money_source_credits_path(@loan, amount: "200000", mode: "recurring")

    assert_response :success
    assert_match "Cada cuota", @response.body
    assert_equal 0, @loan.reload.credit_scenarios.count
  end

  test "recording an extra payment creates a real expense + payment and moves the credit" do
    create_projection
    account = @user.money_sources.create!(name: "Cuenta Ahorros", kind: "account", starting_balance: 500_000)
    balance_before = @loan.reload.credit_account.outstanding_balance.to_d

    post money_source_credit_extras_path(@loan), params: {
      date: Date.current, extra_amount: "300000", application_type: "reduce_term",
      funding_money_source_id: account.id, note: "Aguinaldo"
    }

    assert_redirected_to money_source_path(@loan)
    extra = @loan.reload.credit_extra_payments.last
    assert_equal "reduce_term", extra.application_type
    assert_equal BigDecimal("300000"), extra.amount
    assert_equal BigDecimal("300000"), extra.principal_reduction

    # Real expense: the money actually leaves the funding account.
    assert_equal BigDecimal("200_000"), account.reload.balance
    assert_equal "expense", extra.expense.kind
    # Real payment: principal-only distribution applied to the debt.
    assert_equal BigDecimal("300000"), extra.payment.principal_amount.to_d
    assert_equal BigDecimal("0"), extra.payment.interest_amount.to_d
    assert_equal balance_before - BigDecimal("300000"),
                 @loan.credit_account.reload.outstanding_balance.to_d
    # The payment is listed with the loan's own payments.
    assert_includes @loan.reload.payments.map(&:id), extra.payment.id
  end

  test "recording an extra payment without a funding source is rejected" do
    create_projection

    post money_source_credit_extras_path(@loan), params: {
      date: Date.current, extra_amount: "300000", application_type: "reduce_term"
    }

    assert_redirected_to money_source_credits_path(@loan)
    assert @loan.reload.credit_extra_payments.empty?
  end

  test "prepay distributes the covered installments at face value" do
    create_projection
    account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 2_000_000)

    post money_source_credit_extras_path(@loan), params: {
      date: Date.current, extra_amount: "900000", application_type: "prepay_installments",
      funding_money_source_id: account.id
    }

    assert_redirected_to money_source_path(@loan)
    payment = @loan.reload.credit_extra_payments.last.payment
    assert_equal BigDecimal("900000"), payment.amount.to_d
    # 288,000 + 290,880 + 293,788.80 of capital; the rest is pre-collected interest.
    assert_equal BigDecimal("872668.8"), payment.principal_amount.to_d
    assert_equal BigDecimal("27331.2"), payment.interest_amount.to_d
  end

  test "destroying an extra payment removes it from the history" do
    create_projection
    account = @user.money_sources.create!(name: "Ahorros abonos", kind: "account")
    Credits::ExtraPayments::Create.call(money_source: @loan, funding_money_source: account,
                                        date: Date.current, amount: "300000",
                                        application_type: "reduce_term")
    extra = @loan.credit_extra_payments.last

    delete money_source_credit_extra_path(@loan, extra)

    assert_redirected_to money_source_credits_path(@loan)
    assert_equal 0, @loan.reload.credit_extra_payments.count
  end

  private

  def create_projection
    @loan.create_credit_account!(
      outstanding_balance: 1_200_000, interest_rate: 1.0, interest_rate_type: "monthly",
      installment_amount: 300_000, installment_count: 5, installments_paid: 0,
      start_date: Date.new(2026, 1, 5), payment_frequency: "monthly"
    )
    Credits::Projection::Builder.call(money_source: @loan).result
  end

  def create_scenario_record(index)
    @loan.credit_scenarios.create!(
      name: "Escenario #{index + 1}",
      params: { "amount" => "100000", "after_period" => 1 },
      kind: "reduce_term",
      results: { "interest_saved" => "1000" }, computed_at: Time.current
    )
  end
end
