# frozen_string_literal: true

class ExpenseCandidatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_candidate, only: [ :show, :update, :confirm, :discard ]
  before_action :set_categories, only: [ :show ]
  before_action :set_money_sources, only: [ :show ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def index
    @candidates = current_user.expense_candidates.includes(:category, :money_source)
    @candidates = @candidates.where(status: params[:status]) if params[:status].present?
    @candidates = @candidates.order(created_at: :desc)
  end

  def show
  end

  def update
    if @candidate.update(candidate_params)
      @candidate.recalculate_missing_fields!
      @candidate.recalculate_status!
      redirect_to expense_candidate_path(@candidate), notice: t("expense_candidates.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end

  def confirm
    if @candidate.confirmed? && @candidate.expense_id.present?
      redirect_to expense_candidate_path(@candidate), notice: t("expense_candidates.already_confirmed")
      return
    end

    unless @candidate.missing_fields.empty?
      redirect_to expense_candidate_path(@candidate), alert: t("expense_candidates.missing_fields")
      return
    end

    @candidate.confirm!
    redirect_to expense_candidates_path, notice: t("expense_candidates.confirmed")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to expense_candidate_path(@candidate), alert: e.message
  end

  def discard
    @candidate.discard!
    redirect_to expense_candidates_path, notice: t("expense_candidates.discarded")
  end

  private

  def set_candidate
    @candidate = current_user.expense_candidates.find(params[:id])
  end

  def set_categories
    @categories = Category.for_user(current_user).expenses.order(:name)
  end

  def set_money_sources
    @money_sources = current_user.money_sources.active.order(:kind, :name)
  end

  def candidate_params
    params.require(:expense_candidate).permit(
      :amount, :date, :description, :category_id, :money_source_id,
      :original_input, :original_text, :confidence
    )
  end

  def not_found
    head :not_found
  end
end
