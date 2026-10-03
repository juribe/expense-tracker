# frozen_string_literal: true

class ExpenseCandidatesController < ApplicationController
  include BulkParamsParsing

  before_action :authenticate_user!
  before_action :set_candidate, only: [ :show, :update, :confirm, :discard, :accept_suggestion ]
  before_action :set_categories, only: [ :show, :index, :bulk_update, :bulk_confirm ]
  before_action :set_money_sources, only: [ :show, :index, :bulk_update, :bulk_confirm ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def index
    @candidates = current_user.expense_candidates.includes(:category, :money_source)
    @status = params[:status].presence || "needs_review"
    @status = "needs_review" unless %w[needs_review discarded].include?(@status)
    @candidates = @candidates.where(status: @status)
    @candidates = @candidates.order(created_at: :desc)
                             .paginate(page: params[:page], per_page: ApplicationController::PER_PAGE)
  end

  def show
  end

  def update
    if @candidate.update(candidate_params)
      @candidate.recalculate_missing_fields!
      @candidate.recalculate_status!
      redirect_to expense_candidate_path(@candidate), notice: t("expense_candidates.updated", default: "Candidato actualizado.")
    else
      render :show, status: :unprocessable_entity
    end
  end

  def confirm
    if @candidate.confirmed? && @candidate.expense_id.present?
      redirect_to expense_candidate_path(@candidate), notice: t("expense_candidates.already_confirmed", default: "Este candidato ya fue confirmado.")
      return
    end

    unless @candidate.missing_fields.empty?
      redirect_to expense_candidate_path(@candidate), alert: t("expense_candidates.missing_fields", default: "Faltan campos por completar.")
      return
    end

    @candidate.confirm!
    redirect_to expense_candidates_path, notice: t("expense_candidates.confirmed", default: "Candidato confirmado.")
  rescue ActiveRecord::RecordInvalid, Expenses::Create::Invalid => e
    redirect_to expense_candidate_path(@candidate), alert: e.message
  end

  def discard
    @candidate.discard!
    redirect_to expense_candidates_path, notice: t("expense_candidates.discarded", default: "Candidato descartado.")
  end

  # POST /expense_candidates/:id/accept_suggestion
  def accept_suggestion
    name = @candidate.category_suggestion.to_s.strip
    if name.blank?
      redirect_to expense_candidate_path(@candidate),
                  alert: t("expense_candidates.no_suggestion", default: "No hay sugerencia de categoría.")
      return
    end

    resolved = Categories::ClosestResolver.call(user: current_user, name: name)
    category = resolved.category ||
               Category.create!(name: name.split.map(&:capitalize).join(" "), user: current_user, is_default: false, category_type: "expense")
    @candidate.update!(category_id: category.id, category_suggestion: nil)
    @candidate.recalculate_missing_fields!
    @candidate.recalculate_status!

    redirect_to expense_candidate_path(@candidate),
                notice: t("expense_candidates.suggestion_accepted",
                          default: "Categoría \"#{category.name}\" asignada.")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to expense_candidate_path(@candidate), alert: e.message
  end

  # PATCH /expense_candidates/bulk_update
  # Updates category and/or money source on selected candidates.
  def bulk_update
    result = ExpenseCandidates::BulkUpdate.call(
      user: current_user,
      ids: params[:candidate_ids],
      category_id: params[:category_id],
      money_source_id: params[:money_source_id]
    )

    case result.error_key
    when nil
      redirect_to expense_candidates_path,
                  notice: t("expense_candidates.bulk_updated", count: result.updated_count, default: "#{result.updated_count} candidatos actualizados.")
    when :no_selection
      redirect_to expense_candidates_path, alert: t("expense_candidates.no_selection", default: "No hay candidatos seleccionados.")
    when :nothing_to_change
      redirect_to expense_candidates_path, alert: t("expense_candidates.choose_category_or_source", default: "Elige una categoría o fuente de dinero.")
    when :category_not_found
      redirect_to expense_candidates_path, alert: t("expense_candidates.update_category_not_found", default: "Categoría no encontrada.")
    when :source_not_found
      redirect_to expense_candidates_path, alert: t("expense_candidates.update_source_not_found", default: "Fuente de dinero no encontrada.")
    end
  end

  # POST /expense_candidates/bulk_confirm
  # Updates fields then confirms each selected candidate into an expense.
  def bulk_confirm
    result = ExpenseCandidates::BulkConfirm.call(
      user: current_user,
      ids: params[:candidate_ids],
      category_id: params[:category_id],
      money_source_id: params[:money_source_id]
    )

    if result.failure?
      redirect_to expense_candidates_path,
                  alert: t("expense_candidates.no_selection", default: "No hay candidatos seleccionados.")
      return
    end

    if result.errors.empty?
      redirect_to expense_candidates_path,
                  notice: t("expense_candidates.bulk_confirmed", count: result.confirmed_count, default: "#{result.confirmed_count} candidatos confirmados.")
    else
      redirect_to expense_candidates_path,
                  alert: t("expense_candidates.bulk_confirm_partial",
                           confirmed: result.confirmed_count, failed: result.errors.length,
                           default: "#{result.confirmed_count} confirmados, #{result.errors.length} fallidos.")
    end
  end

  # POST /expense_candidates/bulk_discard
  # Marks the selected reviewable candidates as discarded.
  def bulk_discard
    result = ExpenseCandidates::BulkDiscard.call(user: current_user, ids: params[:candidate_ids])

    if result.success?
      redirect_to expense_candidates_path,
                  notice: t("expense_candidates.bulk_discarded", count: result.discarded_count,
                            default: "#{result.discarded_count} candidatos descartados.")
    else
      redirect_to expense_candidates_path,
                  alert: t("expense_candidates.no_selection", default: "No hay candidatos seleccionados.")
    end
  end

  private

  def set_candidate
    @candidate = current_user.expense_candidates.find(params[:id])
  end

  def set_categories
    @categories = Category.for_user(current_user).expenses.order(:name)
  end

  def set_money_sources
    @money_sources = MoneySource.payment_origins(current_user)
  end

  def candidate_params
    params.expect(expense_candidate: [
      :amount, :date, :description, :category_id, :money_source_id,
      :original_input, :original_text, :confidence
    ])
  end

  def not_found
    head :not_found
  end
end
