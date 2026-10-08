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

  def schedule
    @projection = @loan.credit_projection
    return redirect_to_reconstruct if @projection.nil?

    @view = %w[full actual].include?(params[:view]) ? params[:view] : "future"
    render :schedule, layout: false
  end

  def create_scenario
    result = Credits::Scenarios::Create.call(money_source: @loan, kind: params[:kind],
                                             name: params[:name], params: scenario_params)
    if result.success?
      redirect_to money_source_credits_path(@loan), notice: t("credits.scenarios.created")
    else
      redirect_to money_source_credits_path(@loan), alert: result.errors.to_sentence
    end
  end

  def destroy_scenario
    scenario = @loan.credit_scenarios.find(params[:scenario_id])
    scenario.destroy!
    redirect_to money_source_credits_path(@loan), notice: t("credits.scenarios.deleted")
  end

  private

  def set_loan
    @loan = current_user.money_sources.find(params[:money_source_id])
  end

  def reconstruct_params
    params.permit(:balance, :interest_rate, :interest_rate_type, :installment_amount,
                  :original_term, :current_installment_number, :latest_payment_date,
                  :principal_amount, :interest_amount, :insurance_amount, :other_amount)
          .to_h
          .compact_blank
          .transform_keys do |key|
            { "balance" => "outstanding_balance", "original_term" => "installment_count" }.fetch(key, key)
          end
  end

  def scenario_params
    params.permit(:amount, :every_n_periods, :months_earlier, :after_period)
  end

  def redirect_to_reconstruct
    redirect_to money_source_credit_reconstruct_path(@loan),
                alert: t("credits.needs_data")
  end

  def not_found
    head :not_found
  end
end
