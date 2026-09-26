# frozen_string_literal: true

# Handles AI evaluations for the expense ingestion pipeline. Evaluations run
# datasets through the existing Expense Playground pipeline with a single
# provider/model override and record results for review.
class ExpenseEvaluationsController < ApplicationController
  # GET /expense-evaluations
  def index
    @runs = current_user.evaluation_runs.recent_first.limit(10)
    @runs = @runs.where(dataset_name: params[:dataset]) if params[:dataset].present?

    if request.format.json?
      render json: { runs: @runs.map(&:to_evaluation_entry) }
    end
  end

  # POST /expense-evaluations/start
  def start
    runner = ExpensePlayground::Evaluations::Runner.start(
      user: current_user,
      content: params[:dataset],
      filename: params[:filename],
      provider: params[:provider],
      model: params[:model],
      force_new: params[:force_new]
    )

    if runner.invalid
      render json: { ok: false, errors: runner.errors }, status: :unprocessable_entity
    else
      render json: { ok: true, replayed: runner.replayed, run: runner.run&.to_evaluation_entry }, status: :created
    end
  end

  # GET /expense-evaluations/:id
  def show
    run = current_user.evaluation_runs.find(params[:id])

    render json: {
      run: run.to_evaluation_entry,
      cases: run.evaluation_cases.recent_first.limit(100).map { |c| case_entry(c) }
    }
  end

  # GET /expense-evaluations/:id/cases
  def cases
    run = current_user.evaluation_runs.find(params[:id])
    scope = run.evaluation_cases.recent_first
    scope = scope.by_status(params[:status]) if params[:status].present?
    scope = scope.by_message(params[:q]) if params[:q].present?

    render json: {
      cases: scope.limit(200).map { |c| case_entry(c) },
      total: run.evaluation_cases.count,
      counts: run.evaluation_cases.group(:status).count
    }
  end

  # POST /expense-evaluations/:id/retry
  def retry
    run = current_user.evaluation_runs.find(params[:id])
    scope = params[:all] == "true" ? %w[passed failed error] : %w[failed error]
    reset_cases = run.evaluation_cases.where(status: scope)

    reset_cases.each do |case_record|
      case_record.update!(status: "pending", error: nil)
      ExpensePlaygroundEvaluationCaseJob.perform_later(case_record.id)
    end

    if reset_cases.exists?
      run.update!(status: "running", completed_at: nil, started_at: Time.current)
    end

    render json: { ok: true, rerun_count: reset_cases.size }
  end

  # POST /expense-evaluations/:id/cases/:case_id/map
  def map_case
    run = current_user.evaluation_runs.find(params[:id])
    case_record = run.evaluation_cases.find(params[:case_id])

    category = resolve_mapping_category!(case_record, params[:mapping_action].to_s)

    activity = (case_record.actual_json || {})["activity"].presence || case_record.message
    mapped = ActivityClassification.record!(
      user: current_user,
      name: activity,
      category: category,
      source: "user"
    )

    render json: { ok: true, mapped: mapped.present?, category: category.respond_to?(:name) ? category.name : category.to_s }
  rescue ActiveRecord::RecordNotFound
    render json: { ok: false, errors: [ "No encontrado" ] }, status: :not_found
  rescue ArgumentError => e
    render json: { ok: false, errors: [ e.message ] }, status: :unprocessable_entity
  end

  private

  def case_entry(case_record)
    {
      id: case_record.id,
      row_number: case_record.row_number,
      status: case_record.status,
      message: case_record.message,
      expected_json: case_record.expected_json,
      actual_json: case_record.actual_json,
      field_results: case_record.field_results,
      json_valid: case_record.json_valid,
      latency_ms: case_record.latency_ms,
      input_tokens: case_record.input_tokens,
      output_tokens: case_record.output_tokens,
      cost: case_record.cost&.to_f,
      error: case_record.error,
      attempts: case_record.attempts,
      mapped: classification_for_case(case_record),
      suggested_category: case_suggestion(case_record)
    }
  end

  def classification_for_case(case_record)
    activity = (case_record.actual_json || {})["activity"].presence || case_record.message
    ActivityClassification.lookup(user: current_user, name: activity)&.source == "user"
  end

  def case_suggestion(case_record)
    actual = case_record.actual_json
    return nil if actual.blank?

    received = actual["category"].to_s
    return nil if received.blank?

    activity = actual["activity"].presence || case_record.message
    return nil if activity.blank?

    resolved = Categories::ClosestResolver.call(user: current_user, name: received, activity: activity, record: false)
    return nil unless resolved.matched_by.in?(%i[variant similar])

    resolved.category&.name
  rescue StandardError
    nil
  end

  def resolve_mapping_category!(case_record, action)
    case action
    when "use_existing"
      Category.for_user(current_user).find(params[:category_id])
    when "create"
      name = params[:new_category_name].to_s.strip
      raise ArgumentError, "category name required" if name.blank?

      Categories::ClosestResolver.call(user: current_user, name: name).category ||
        Category.create!(name: name, user: current_user, is_default: false)
    when "accept_received"
      received = (case_record.actual_json || {})["category"].to_s
      raise ArgumentError, "received case has no category to accept" if received.blank?

      Categories::ClosestResolver.call(user: current_user, name: received).category ||
        Category.create!(name: received, user: current_user, is_default: false)
    else
      raise ArgumentError, "unknown mapping action #{action.inspect}"
    end
  end
end
