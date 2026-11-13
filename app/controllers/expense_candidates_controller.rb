# frozen_string_literal: true

class ExpenseCandidatesController < ApplicationController
  include BulkParamsParsing

  MISSING_FILTER_FIELDS = %w[amount date description category_id money_source_id].freeze

  before_action :authenticate_user!
  before_action :set_candidate, only: [ :show, :update, :confirm, :discard, :accept_suggestion, :restore ]
  before_action :set_categories, only: [ :show, :update, :index, :bulk_update, :bulk_confirm ]
  before_action :set_money_sources, only: [ :show, :update, :index, :bulk_update, :bulk_confirm ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def index
    @status = params[:status].presence || "needs_review"
    @status = "needs_review" unless %w[needs_review discarded].include?(@status)

    queue_scope = current_user.expense_candidates
    @pending_count = queue_scope.needs_review.count
    @discarded_count = queue_scope.discarded.count
    @total_count = @pending_count + @discarded_count
    @sources = queue_scope.where.not(source: nil).distinct.order(:source).pluck(:source)
    @filters_active = filter_params_present?

    @candidates = filtered_candidates
                  .includes(:category, :money_source)
                  .order(created_at: :desc)
                  .paginate(page: params[:page], per_page: ApplicationController::PER_PAGE)
  end

  def show
  end

  def update
    if @candidate.update(candidate_params)
      @candidate.recalculate_missing_fields!
      @candidate.recalculate_status!
      @candidate.remember_category!
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

  # POST /expense_candidates/:id/restore
  # Returns a discarded candidate to the review queue. It becomes `ready`
  # or `needs_review` depending on the information it still has.
  def restore
    @candidate.restore!
    redirect_to expense_candidates_path,
                notice: t("expense_candidates.queue.restored", default: "Candidato recuperado.")
  rescue ActiveRecord::RecordInvalid
    redirect_to expense_candidates_path(status: "discarded"),
                alert: t("expense_candidates.queue.restore_failed", default: "No pudimos recuperar el candidato.")
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
    @candidate.remember_category!

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
      redirect_to bulk_redirect_path,
                  notice: t("expense_candidates.bulk_updated", count: result.updated_count, default: "#{result.updated_count} candidatos actualizados.")
    when :no_selection
      redirect_to bulk_redirect_path, alert: t("expense_candidates.no_selection", default: "No hay candidatos seleccionados.")
    when :nothing_to_change
      redirect_to bulk_redirect_path, alert: t("expense_candidates.choose_category_or_source", default: "Elige una categoría o fuente de dinero.")
    when :category_not_found
      redirect_to bulk_redirect_path, alert: t("expense_candidates.update_category_not_found", default: "Categoría no encontrada.")
    when :source_not_found
      redirect_to bulk_redirect_path, alert: t("expense_candidates.update_source_not_found", default: "Fuente de dinero no encontrada.")
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
      redirect_to bulk_redirect_path,
                  alert: t("expense_candidates.no_selection", default: "No hay candidatos seleccionados.")
      return
    end

    if result.errors.empty?
      redirect_to bulk_redirect_path,
                  notice: t("expense_candidates.bulk_confirmed", count: result.confirmed_count, default: "#{result.confirmed_count} candidatos confirmados.")
    else
      failed_names = result.errors.map { |error| error[:description].presence || error[:id] }.join(", ")
      redirect_to bulk_redirect_path,
                  alert: t("expense_candidates.bulk_confirm_partial",
                           confirmed: result.confirmed_count, failed: result.errors.length, names: failed_names,
                           default: "#{result.confirmed_count} confirmados, #{result.errors.length} fallidos: #{failed_names}.")
    end
  end

  # POST /expense_candidates/bulk_discard
  # Marks the selected reviewable candidates as discarded.
  def bulk_discard
    result = ExpenseCandidates::BulkDiscard.call(user: current_user, ids: params[:candidate_ids])

    if result.success?
      redirect_to bulk_redirect_path,
                  notice: t("expense_candidates.bulk_discarded", count: result.discarded_count,
                            default: "#{result.discarded_count} candidatos descartados.")
    else
      redirect_to bulk_redirect_path,
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

  def filtered_candidates
    scope = current_user.expense_candidates.where(status: @status)
    scope = search_candidates(scope)
    scope = filter_by_source(scope)
    scope = filter_by_category(scope)
    scope = filter_by_money_source(scope)
    filter_by_missing_information(scope)
  end

  def search_candidates(scope)
    query = params[:q].to_s.strip
    return scope if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    scope.where("description ILIKE :pattern OR original_text ILIKE :pattern", pattern: pattern)
  end

  def filter_by_source(scope)
    source = params[:source].to_s
    return scope if source.blank?
    return scope.where(source: source) if @sources.include?(source)

    scope.none
  end

  def filter_by_category(scope)
    return scope if params[:category_id].blank?

    category_id = UuidParams.normalize(params[:category_id])
    return scope.none if category_id.nil?

    scope.where(category_id: category_id)
  end

  def filter_by_money_source(scope)
    return scope if params[:money_source_id].blank?

    money_source_id = UuidParams.normalize(params[:money_source_id])
    return scope.none if money_source_id.nil?

    scope.where(money_source_id: money_source_id)
  end

  # `missing_fields` is derived data and can be stale on freshly persisted
  # candidates, so these filters inspect the real columns instead.
  def filter_by_missing_information(scope)
    missing = params[:missing].to_s
    return scope if missing.blank?

    case missing
    when "any"
      scope.where("amount IS NULL OR date IS NULL OR description IS NULL OR description = '' OR category_id IS NULL OR money_source_id IS NULL")
    when "none"
      scope.where("amount IS NOT NULL AND date IS NOT NULL AND description IS NOT NULL AND description <> '' AND category_id IS NOT NULL AND money_source_id IS NOT NULL")
    when *MISSING_FILTER_FIELDS
      filter_by_single_missing_field(scope, missing)
    else
      scope.none
    end
  end

  def filter_by_single_missing_field(scope, field)
    case field
    when "amount" then scope.where(amount: nil)
    when "date" then scope.where(date: nil)
    when "description" then scope.where("description IS NULL OR description = ''")
    when "category_id" then scope.where(category_id: nil)
    when "money_source_id" then scope.where(money_source_id: nil)
    else scope.none
    end
  end

  def filter_params_present?
    params[:q].to_s.strip.present? ||
      %i[source category_id money_source_id missing].any? { |key| params[key].present? }
  end

  # Bulk actions keep the user on the tab where they started.
  def bulk_redirect_path
    params[:status].to_s == "discarded" ? expense_candidates_path(status: "discarded") : expense_candidates_path
  end

  def candidate_params
    permitted = params.expect(expense_candidate: [
      :amount, :date, :description, :category_id, :money_source_id,
      :original_input, :original_text, :confidence
    ])

    %i[category_id money_source_id].each do |key|
      value = permitted[key]
      next if value.blank?

      normalized = UuidParams.normalize(value)
      normalized ? permitted[key] = normalized : permitted.delete(key)
    end

    permitted
  end

  def not_found
    head :not_found
  end
end
