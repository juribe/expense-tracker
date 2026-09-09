# frozen_string_literal: true

# Internal testing page for the expense ingestion pipeline. It processes
# inputs (text / image / text+image) into an ExpenseCandidate WITHOUT creating
# a real expense; persistence only happens when the user explicitly confirms
# through +create+.
#
# Every processing execution is recorded as an ExpensePlaygroundRun (without
# raw image payloads) so the history survives sessions and future evaluation
# features can compare runs against expected results.
class ExpensePlaygroundController < ApplicationController
  before_action :set_categories, only: :show

  def show; end

  # POST /expense-playground/process
  # Runs the pipeline and returns the ExpenseCandidate + every pipeline stage
  # for debugging. Never writes an Expense.
  def run
    input = ExpensePlayground::Adapters::Registry.build(params[:type], input_params)

    return render_invalid_input(input) unless input.valid?

    result = ExpensePlayground::ProcessingService.call(user: current_user, input: input)
    run_record = persist_run(input, result)

    render json: {
      ok: result.ok?,
      run_id: run_record&.id,
      engine: result.engine,
      duration_ms: result.duration_ms,
      candidate: result.candidate&.as_json,
      errors: result.errors,
      warnings: result.warnings,
      steps: result.steps,
      evaluation: result.candidate && expected_params.present? ? run_evaluation(result.candidate) : nil
    }, status: result.ok? ? :ok : :unprocessable_entity
  end

  # GET /expense-playground/history
  # Recent pipeline executions for the current user.
  def history
    runs = current_user.expense_playground_runs.recent_first.limit(10)

    render json: { runs: runs.map(&:to_history_entry) }
  end

  # POST /expense-playground/create
  # Explicitly persists a reviewed candidate through the app's single expense
  # creation entry point (validations and rules are NOT bypassed).
  def create
    candidate = ExpenseCandidate.from_h(candidate_params)

    return render json: { ok: false, errors: candidate.errors }, status: :unprocessable_entity unless candidate.valid?

    expense = Expenses::Create.call(
      user: current_user,
      amount: candidate.amount,
      description: candidate.description.presence || candidate.merchant.presence || candidate.category_name,
      category: candidate_category(candidate),
      occurred_at: candidate.date,
      source: candidate.source.presence || "playground",
      money_source: candidate_money_source(candidate)
    )
    link_run_to_expense(expense)

    render json: {
      ok: true,
      created: true,
      expense_id: expense.id,
      expense_path: expense_path(expense),
      message: I18n.t("playground.expense_created", default: "Expense created successfully.")
    }, status: :created
  rescue Expenses::Create::Invalid => e
    render json: { ok: false, errors: [ e.message ] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { ok: false, errors: [ "The selected category or money source no longer exists." ] },
           status: :unprocessable_entity
  end

  private

  def set_categories
    @categories = Category.for_user(current_user)
    @money_sources = current_user.money_sources.active.order(:name)
  end

  # Raw channel params. Adapters turn these into an ExpensePlayground::Input;
  # image payloads are used in-memory only and never persisted.
  def input_params
    params.permit(:text, :image_data, metadata: {})
  end

  def expected_params
    params.permit(expected: %i[amount category description merchant date source])[:expected]
  end

  def run_evaluation(candidate)
    ExpensePlayground::Evaluation.call(candidate: candidate, expected: expected_params)
  end

  def candidate_params
    params.permit(candidate: %i[
      amount currency category_id category_name description merchant
      date source confidence money_source_id money_source_name
    ])[:candidate] || {}
  end

  # Best-effort audit of pipeline executions: a persistence failure must never
  # block processing, and no raw image payload ever reaches the DB.
  def persist_run(input, result)
    ExpensePlaygroundRun.record!(
      user: current_user,
      input_type: input.type,
      input_label: params[:input_label].presence || input.text,
      result: result
    )
  rescue StandardError => e
    Rails.logger.warn("[expense_playground] run persistence failed: #{e.class}: #{e.message}")
    nil
  end

  def link_run_to_expense(expense)
    return if params[:run_id].blank?

    current_user.expense_playground_runs.where(id: params[:run_id]).find_each do |run|
      run.update!(expense_id: expense.id)
    end
  rescue StandardError => e
    Rails.logger.warn("[expense_playground] run linking failed: #{e.class}: #{e.message}")
  end

  # Categories must be scoped to the current user; Expenses::Create accepts
  # raw ids/names, so ownership is enforced here before persisting.
  def candidate_category(candidate)
    if candidate.category_id.present?
      Category.for_user(current_user).find_by!(id: candidate.category_id)
    else
      candidate.category_name
    end
  end

  def candidate_money_source(candidate)
    return nil if candidate.money_source_id.blank?

    current_user.money_sources.find(candidate.money_source_id)
  end

  def render_invalid_input(input)
    render json: { ok: false, errors: input.errors }, status: :unprocessable_entity
  end
end
