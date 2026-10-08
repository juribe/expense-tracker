# frozen_string_literal: true

# CreditsController
# Credit intelligence dashboard for a debt money source. Purely
# informational: builds/persists the credit projection (reconstruction
# included), runs extra-payment simulators as saved scenarios and renders
# the comparison + amortization table. Never mutates the credit itself.
class CreditsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_loan

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def show
    result = Credits::Projection::Builder.call(money_source: @loan)
    return redirect_to_reconstruct if result.failure?

    @projection = result.result
    @comparison = Credits::Comparison.call(projection: @projection, objective: params[:objective])
    @view = %w[full actual].include?(params[:view]) ? params[:view] : "future"
    load_quick_comparison
    load_opportunity
  end

  def reconstruct
    @inputs = Credits::DataCollector.call(money_source: @loan)
  end

  def build
    result = Credits::Projection::Builder.call(money_source: @loan,
                                               overrides: reconstruct_params, force: true)
    if result.success?
      redirect_to money_source_credits_path(@loan), notice: t("credits.rebuilt")
    else
      @inputs = Credits::DataCollector.call(money_source: @loan, overrides: reconstruct_params)
      flash.now[:alert] = result.errors.to_sentence
      render :reconstruct, status: :unprocessable_entity
    end
  end

  def refresh
    Credits::Projection::Builder.call(money_source: @loan, force: true)
    redirect_to money_source_credits_path(@loan), notice: t("credits.refreshed")
  end

  def create_scenario
    result = Credits::Scenarios::Create.call(money_source: @loan, kind: params[:kind],
                                             name: params[:name], params: scenario_params)
    if result.success?
      redirect_to money_source_credits_path(@loan), notice: t("credits.scenarios.created")
    else
      redirect_to money_source_credits_path(@loan, amount: scenario_params["amount"]),
                  alert: result.errors.to_sentence
    end
  end

  def destroy_scenario
    scenario = @loan.credit_scenarios.find(params[:scenario_id])
    scenario.destroy!
    redirect_to money_source_credits_path(@loan), notice: t("credits.scenarios.deleted")
  end

  def record_extra
    funding = current_user.money_sources.payment_sources.find_by(id: params[:funding_money_source_id])
    result = Credits::ExtraPayments::Create.call(money_source: @loan, funding_money_source: funding,
                                                 date: params[:date],
                                                 amount: params[:extra_amount],
                                                 application_type: params[:application_type],
                                                 note: params[:note])
    if result.success?
      redirect_to money_source_path(@loan), notice: t("credits.extras.recorded")
    else
      redirect_to money_source_credits_path(@loan), alert: result.errors.to_sentence
    end
  end

  def destroy_extra
    extra = @loan.credit_extra_payments.find(params[:extra_id])
    extra.discard!
    redirect_to money_source_credits_path(@loan), notice: t("credits.extras.deleted")
  end

  private

  def set_loan
    @loan = current_user.money_sources.find(params[:money_source_id])
  end

  def reconstruct_params
    params.permit(:balance, :interest_rate, :interest_rate_type, :installment_amount,
                  :original_term, :current_installment_number, :latest_payment_date,
                  :principal_amount, :interest_amount, :insurance_amount, :other_amount,
                  :insurance_assumption, :interest_calculation, :extra_payment_default)
          .to_h
          .compact_blank
          .transform_keys do |key|
            { "balance" => "outstanding_balance", "original_term" => "installment_count" }.fetch(key, key)
          end
  end

  def scenario_params
    params.permit(:amount, :repeat_every, :every_n_periods, :months_earlier, :after_period)
          .to_h
          .transform_keys { |key| key == "every_n_periods" ? "repeat_every" : key }
  end

  # "¿Qué hago con esta plata?": transient side-by-side strategy comparison
  # for the entered amount. Nothing is persisted here. The recurring mode
  # simulates paying the amount as a constant extra every installment.
  def load_quick_comparison
    return if params[:amount].blank?
    return if @projection.nil?

    amount = params[:amount].to_s.gsub(/[^\d.,]/, "")
    return if amount.blank?

    @quick_comparison = Credits::Comparison.quick(projection: @projection, amount: amount,
                                                  mode: recurring_quick_mode? ? "recurring" : "once")
  rescue ArgumentError, TypeError
    nil
  end

  def recurring_quick_mode?
    params[:mode] == "recurring"
  end

  # Opportunity hint: the impact of putting one extra installment into the
  # credit. Cheap: reads the persisted schedule and runs one simulation.
  def load_opportunity
    @opportunity = nil
    return if @projection.nil?
    return if @quick_comparison.present? || @loan.credit_scenarios.exists?

    installment_total = (@projection.summary["installment_amount"].to_d +
                         @projection.summary["future_insurance"].to_d / [ @projection.summary["remaining_installments"].to_i, 1 ].max)
    results = Credits::Simulator.run(projection: @projection, strategy: "reduce_term",
                                     params: { "amount" => installment_total.round(2) })
    @opportunity = { amount: installment_total, results: results }
  rescue ActiveRecord::RecordNotFound, ArgumentError, TypeError
    nil
  end

  def redirect_to_reconstruct
    redirect_to money_source_credit_reconstruct_path(@loan),
                alert: t("credits.needs_data")
  end

  def not_found
    head :not_found
  end
end
