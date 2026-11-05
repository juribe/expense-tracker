# frozen_string_literal: true

class FinancialHabitsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_analysis, only: [ :show, :refresh, :status ]

  def show
    @analysis_state = FinancialHabits::AnalysisState.read(current_user.id)
    @narrative = narrative.fetch

    if @narrative.nil?
      @narrative = narrative.deterministic
      @analysis_pending = @analysis_state == "pending" || enqueue_analysis
    else
      @analysis_pending = @analysis_state == "pending"
    end
  end

  def detail
    result = FinancialHabits::Detail.new(user: current_user, key: params[:key]).call
    if result[:state] == :not_found
      return redirect_to financial_habits_path, alert: "No encontramos ese análisis."
    end

    @analysis = result[:analysis]
    @discovery = result[:discovery]
    @detail = result[:detail]
  end

  def refresh
    unless FinancialHabits::Narrative.ai_available?
      return respond_with_state("unavailable", :ok)
    end

    if FinancialHabits::AnalysisState.acquire_lock(current_user.id)
      narrative.cache.delete(narrative.cache_key)
      FinancialHabits::AnalysisState.write(current_user.id, "pending")
      FinancialHabitsAnalysisJob.perform_later(current_user.id)
      respond_with_state("pending", :accepted)
    else
      respond_with_state("pending", :accepted)
    end
  end

  def status
    render json: { state: FinancialHabits::AnalysisState.read(current_user.id) }
  end

  private

  def set_analysis
    @analysis = FinancialHabits::Analysis.new(user: current_user).call
  end

  def narrative
    @narrative_service ||= FinancialHabits::Narrative.new(user: current_user, analysis: @analysis)
  end

  def enqueue_analysis
    return false unless FinancialHabits::Narrative.ai_available?
    return false unless @analysis[:state] == :ok
    return false unless Array(@analysis[:discoveries]).any?
    return false unless FinancialHabits::AnalysisState.acquire_lock(current_user.id)

    FinancialHabits::AnalysisState.write(current_user.id, "pending")
    FinancialHabitsAnalysisJob.perform_later(current_user.id)
    true
  end

  def respond_with_state(state, status)
    respond_to do |format|
      format.json { render json: { state: state }, status: status }
      format.html do
        redirect_back fallback_location: financial_habits_path,
                      notice: state
      end
    end
  end
end