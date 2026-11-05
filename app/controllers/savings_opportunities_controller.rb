# frozen_string_literal: true

# SavingsOpportunitiesController
# GET  /savings_opportunities          — Pro-only savings analysis page.
# POST /savings_opportunities/refresh  — request a fresh AI narrative.
# GET  /savings_opportunities/status   — poll the background analysis state.
# POST /savings_opportunities/scenario — turn a simulation into a goal draft.
#
# The premium gate reuses PremiumAccess; the deterministic financial analysis
# never depends on the AI provider.
class SavingsOpportunitiesController < ApplicationController
  require_premium

  before_action :set_analysis, only: [ :show, :refresh, :scenario ]

  def show
    @analysis_state = SavingsOpportunities::AnalysisState.read(current_user.id)
    @narrative = narrative.fetch

    if @narrative.nil?
      @narrative = narrative.deterministic
      @analysis_pending = @analysis_state == "pending" || enqueue_analysis
    else
      @analysis_pending = @analysis_state == "pending"
    end
  end

  def refresh
    unless SavingsOpportunities::Narrative.ai_available?
      return respond_with_state("unavailable", :ok)
    end

    if SavingsOpportunities::AnalysisState.acquire_lock(current_user.id)
      narrative.cache.delete(narrative.cache_key)
      SavingsOpportunities::AnalysisState.write(current_user.id, "pending")
      SavingsOpportunityAnalysisJob.perform_later(current_user.id)
      respond_with_state("pending", :accepted)
    else
      respond_with_state("pending", :accepted)
    end
  end

  def status
    render json: { state: SavingsOpportunities::AnalysisState.read(current_user.id) }
  end

  def scenario
    rows = @analysis[:simulator][:rows]
    total = SavingsOpportunities::Simulator.total(rows: rows, reductions: reductions_param(rows))

    if total.positive?
      redirect_to new_goal_path(
        name: t("savings_opportunities.goal.name", monthly: MoneyFormat.currency(total)),
        target_amount: (total * 12).to_i
      )
    else
      redirect_to savings_opportunities_path, alert: t("savings_opportunities.goal.empty")
    end
  end

  private

  def set_analysis
    @analysis = SavingsOpportunities::Analysis.new(user: current_user).call
  end

  def narrative
    @narrative_service ||= SavingsOpportunities::Narrative.new(user: current_user, analysis: @analysis)
  end

  # First visit: generate the AI narrative in the background when a provider
  # is configured. The short lock makes concurrent page loads harmless.
  def enqueue_analysis
    return false unless SavingsOpportunities::Narrative.ai_available?
    return false unless @analysis[:state] == :ok
    return false unless @analysis[:totals][:opportunities_count].positive?
    return false unless SavingsOpportunities::AnalysisState.acquire_lock(current_user.id)

    SavingsOpportunities::AnalysisState.write(current_user.id, "pending")
    SavingsOpportunityAnalysisJob.perform_later(current_user.id)
    true
  end

  def respond_with_state(state, status)
    respond_to do |format|
      format.json { render json: { state: state }, status: status }
      format.html do
        redirect_back fallback_location: savings_opportunities_path,
                      notice: t("savings_opportunities.refresh.#{state}", default: t("savings_opportunities.refresh.pending"))
      end
    end
  end

  # Only keys that match rows computed by the backend reach the simulator.
  # Percentages are parsed and clamped inside Simulator.total.
  def reductions_param(rows)
    raw = params[:reductions]
    return {} unless raw.respond_to?(:[])

    rows.each_with_object({}) do |row, reductions|
      value = raw[row[:id].to_s]
      reductions[row[:id].to_s] = value if value.present?
    end
  end
end
