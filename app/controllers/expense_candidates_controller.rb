# frozen_string_literal: true

class ExpenseCandidatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_candidate, only: [ :show, :update, :confirm, :discard ]
  before_action :set_categories, only: [ :show, :index, :bulk_update, :bulk_confirm ]
  before_action :set_money_sources, only: [ :show, :index, :bulk_update, :bulk_confirm ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def index
    @candidates = current_user.expense_candidates.includes(:category, :money_source)
    @status = params[:status].presence || "needs_review"
    @candidates = @candidates.where(status: @status) unless @status == "all"
    @candidates = @candidates.order(created_at: :desc)
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
  rescue ActiveRecord::RecordInvalid => e
    redirect_to expense_candidate_path(@candidate), alert: e.message
  end

  def discard
    @candidate.discard!
    redirect_to expense_candidates_path, notice: t("expense_candidates.discarded", default: "Candidato descartado.")
  end

  # PATCH /expense_candidates/bulk_update
  # Updates category and/or money source on selected candidates.
  def bulk_update
    ids = parse_ids(params[:candidate_ids])
    category_id = params[:category_id].presence
    money_source_id = params[:money_source_id].presence

    return redirect_to expense_candidates_path, alert: t("expense_candidates.no_selection", default: "No hay candidatos seleccionados.") if ids.empty?
    return redirect_to expense_candidates_path, alert: t("expense_candidates.choose_category_or_source", default: "Elige una categoría o fuente de dinero.") if category_id.blank? && money_source_id.blank?
    return redirect_to expense_candidates_path, alert: t("expense_candidates.update_category_not_found", default: "Categoría no encontrada.") if category_id.present? && !Category.for_user(current_user).where(id: category_id).exists?
    return redirect_to expense_candidates_path, alert: t("expense_candidates.update_source_not_found", default: "Fuente de dinero no encontrada.") if money_source_id.present? && !current_user.money_sources.where(id: money_source_id).exists?

    scope = current_user.expense_candidates.where(id: ids)
    count = scope.count

    return redirect_to expense_candidates_path, alert: t("expense_candidates.no_selection", default: "No hay candidatos seleccionados.") if count.zero?

    updates = {}
    updates[:category_id] = category_id.to_i if category_id.present?
    updates[:money_source_id] = money_source_id.to_i if money_source_id.present?

    scope.update_all(updates)

    redirect_to expense_candidates_path, notice: t("expense_candidates.bulk_updated", count: count, default: "#{count} candidatos actualizados.")
  end

  # POST /expense_candidates/bulk_confirm
  # Updates fields then confirms each selected candidate into an expense.
  def bulk_confirm
    ids = parse_ids(params[:candidate_ids])

    return redirect_to expense_candidates_path, alert: t("expense_candidates.no_selection", default: "No hay candidatos seleccionados.") if ids.empty?

    category_id = params[:category_id].present? ? params[:category_id].to_i : nil
    money_source_id = params[:money_source_id].present? ? params[:money_source_id].to_i : nil

    if category_id.present? && !Category.for_user(current_user).where(id: category_id).exists?
      return redirect_to expense_candidates_path, alert: t("expense_candidates.update_category_not_found", default: "Categoría no encontrada.")
    end

    if money_source_id.present? && !current_user.money_sources.where(id: money_source_id).exists?
      return redirect_to expense_candidates_path, alert: t("expense_candidates.update_source_not_found", default: "Fuente de dinero no encontrada.")
    end

    scope = current_user.expense_candidates.where(id: ids)
    confirmed_count = 0
    errors = []

    scope.find_each do |candidate|
      candidate.update(category_id: category_id, money_source_id: money_source_id) if category_id || money_source_id
      candidate.recalculate_missing_fields!
      candidate.recalculate_status!

      if candidate.missing_fields.any?
        errors << { id: candidate.id, description: candidate.description, errors: ["Campos faltantes: #{candidate.missing_fields.join(', ')}"] }
        next
      end

      candidate.confirm!
      confirmed_count += 1
    rescue ActiveRecord::RecordInvalid => e
      errors << { id: candidate.id, description: candidate.description, errors: [e.message] }
    end

    if errors.empty?
      redirect_to expense_candidates_path, notice: t("expense_candidates.bulk_confirmed", count: confirmed_count, default: "#{confirmed_count} candidatos confirmados.")
    else
      redirect_to expense_candidates_path, alert: t("expense_candidates.bulk_confirm_partial", confirmed: confirmed_count, failed: errors.length, default: "#{confirmed_count} confirmados, #{errors.length} fallidos.")
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
    @money_sources = current_user.money_sources.active.order(:kind, :name)
  end

  def candidate_params
    params.expect(expense_candidate: [
      :amount, :date, :description, :category_id, :money_source_id,
      :original_input, :original_text, :confidence
    ])
  end

  def parse_ids(raw)
    Array(raw).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
  end

  def not_found
    head :not_found
  end
end
