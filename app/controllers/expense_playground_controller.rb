# frozen_string_literal: true

# Internal testing page for the expense ingestion pipeline. It processes
# inputs (text / image / text+image / audio) into an ExpenseCandidate WITHOUT
# creating a real expense; persistence only happens when the user explicitly
# confirms through +create+.
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
    input = Expenses::Input.from_params(params[:type], input_params)

    return render_invalid_input(input) unless input.valid?

    result = Expenses::Processor.call(user: current_user, input: input)
    puts "[expense_playground] run result: ok=#{result.ok?} engine=#{result.engine} duration_ms=#{result.duration_ms} candidate=#{result.candidate&.as_json} errors=#{result.errors} warnings=#{result.warnings}"
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

  # GET /expense-playground/ai_summary
  # AI routing observability for the current user: tier usage over the last
  # week plus the most recent resolutions, so it is visible which tier
  # (deterministic / cache / cheap / strong) answered each request.
  def ai_summary
    scope = AiRequest.where(user: current_user).where("created_at > ?", 7.days.ago)

    render json: {
      summary: Ai::Metrics.summary(scope),
      cheap_tier_enabled: Ai.configuration.cheap_enabled?,
      recent: scope.recent_first.limit(10).map do |r|
        {
          task: r.task,
          strategy: r.strategy,
          provider: r.provider,
          model: r.model,
          status: r.status,
          confidence: r.confidence&.to_f,
          escalated: r.escalated,
          latency_ms: r.latency_ms,
          created_at: r.created_at.iso8601
        }
      end
    }
  end

  # GET /expense-playground/evaluations
  # Recent AI evaluations for the current user (recent first).
  def evaluations
    runs = current_user.evaluation_runs.recent_first.limit(10)
    runs = runs.where(dataset_name: params[:dataset]) if params[:dataset].present?

    render json: { runs: runs.map(&:to_evaluation_entry) }
  end

    # POST /expense-playground/evaluations/start
    # Starts an evaluation: validates the dataset, persists the run + cases and
    # enqueues a background job per case. The endpoint is idempotent by
    # dataset+provider/model, so re-submitting the same dataset returns the
    # existing run instead of double-processing it. Pass force_new: true to
    # always start a fresh run (e.g. after renaming/copying a dataset file).
    def start_evaluation
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

  # GET /expense-playground/evaluations/:id
  # A single evaluation: summary + the first page of cases.
  def evaluation
    run = current_user.evaluation_runs.find(params[:id])

    render json: {
      run: run.to_evaluation_entry,
      cases: run.evaluation_cases.recent_first.limit(100).map { |c| case_entry(c) }
    }
  end

  # GET /expense-playground/evaluations/:id/cases
  # Paginated, filterable case list for the progress view.
  def evaluation_cases
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

  # POST /expense-playground/evaluations/:id/retry
  # Re-runs the terminal cases of an evaluation. Pass all=true to re-run
  # passed cases too. Terminal cases are reset to pending and re-enqueued.
  def retry_evaluation
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

  # POST /expense-playground/evaluations/:id/cases/:case_id/mapping
  # Records a user decision about which category an evaluation case should map
  # to, so the review of expected-vs-received is remembered (review log). The
  # decision is stored as user classification knowledge for the case activity.
  #
  #   action = "accept_received"  use whatever the AI resolved to
  #          | "use_existing"     map to Category (params[:category_id])
  #          | "create"           create a new category (params[:new_category_name])
  def map_evaluation_case
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

  # POST /expense-playground/process_file
  # Extracts transactions from an uploaded statement file (PDF/CSV/Excel).
  # Returns the candidates for preview without persisting anything. For
  # password-protected PDFs the caller supplies the password, which is used
  # only to unlock the document and is never persisted.
  def process_file
    result = Expenses::FileProcessor.call(
      user: current_user,
      file_data: params[:file_data],
      filename: params[:filename],
      password: params[:password]
    )

    render json: {
      ok: result.ok?,
      candidates: result.candidates.map(&:as_json),
      sources: result.sources.map(&:to_h),
      duplicates: result.duplicates,
      errors: result.errors,
      warnings: result.warnings,
      steps: result.step_results
    }, status: result.ok? ? :ok : :unprocessable_entity
  end

  # POST /expense-playground/batch_create
  # Creates expenses from reviewed candidates. Every candidate goes through
  # Expenses::Create so validations and rules are not bypassed; failures are
  # collected per row and never silently drop valid transactions.
  def batch_create
    candidates = Array(params[:candidates] || params[:candidate])

    created = []
    errors = []

    candidates.each do |candidate_params|
      candidate = build_batch_candidate(candidate_params)
      unless candidate.valid?
        errors << { index: created.size + errors.size + 1, errors: candidate.errors }
        next
      end

      expense = Expenses::Create.call(
        user: current_user,
        amount: candidate.amount,
        description: candidate.description.presence || candidate.merchant.presence || candidate.category_name,
        category: candidate_category(candidate),
        occurred_at: candidate.date,
        source: "playground_file",
        money_source: candidate_money_source(candidate)
      )
      record_classification!(candidate, expense.category)
      created << { expense_id: expense.id, path: expense_path(expense) }
    rescue Expenses::Create::Invalid => e
      errors << { index: created.size + errors.size + 1, errors: [ e.message ] }
    rescue ActiveRecord::RecordNotFound
      errors << { index: created.size + errors.size + 1, errors: [ "The selected category or money source no longer exists." ] }
    end

    render json: { ok: errors.empty?, created: created, errors: errors }, status: errors.empty? ? :ok : :unprocessable_entity
  end

  # POST /expense-playground/create
  # Explicitly persists a reviewed candidate through the app's single expense
  # creation entry point (validations and rules are NOT bypassed).
  def create
    candidate = ExpenseCandidate.from_h(candidate_params)

    return render json: { ok: false, errors: candidate.errors }, status: :unprocessable_entity unless candidate.valid?

    if candidate.category_id.blank? && candidate.category_name.blank?
      return render json: { ok: false, errors: [ "Assign a category to this expense before confirming." ] },
                    status: :unprocessable_entity
    end

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

  # Resolves the category a user decision maps the case to. Never returns a
  # near-duplicate: names that are very close to an existing category fold into
  # it, and only genuinely-new names create a category.
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

  def set_categories
    @categories = Category.for_user(current_user)
    @money_sources = current_user.money_sources.active.order(:name)
  end

  # Serializes a single evaluation case for the progress/case views.
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

  # Whether the case's activity already has a recorded user decision (review
  # log), so the expected-vs-received table can show accepted mappings.
  def classification_for_case(case_record)
    activity = (case_record.actual_json || {})["activity"].presence || case_record.message
    ActivityClassification.lookup(user: current_user, name: activity)&.source == "user"
  end

  # For the review summary: whether the received category is a near-duplicate
  # of an existing one (folded by variant/similarity). English aliases and
  # learned mappings are deliberate and do not need review.
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

  # Raw channel params. Expenses::Input.from_params reads only the
  # keys each type declares; image, audio and file payloads are used in-memory
  # only and never persisted.
  def input_params
    params.permit(:text, :image_data, :audio_data, :file_data, :filename, :password, metadata: {})
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

  # Builds an ExpenseCandidate from a row of the file-import preview. Follows
  # ExpenseCandidate.from_h but tolerates both hash and string keys so the
  # batch endpoint accepts the same JSON the front-end sends back.
  def build_batch_candidate(row)
    attrs = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
    ExpenseCandidate.from_h(attrs)
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

  # Persists classification knowledge after a file import row is created so
  # repeated activities reuse it in future imports. A category the user
  # changed (vs. what the enrichment suggested) is stored as a user override;
  # unchanged AI/rule classifications are stored for future reuse.
  def record_classification!(candidate, category)
    description = candidate.description.to_s.presence || candidate.merchant.to_s.presence
    return if description.blank? || category.blank?

    suggested = candidate.suggested_category_name.to_s.presence
    source =
      if suggested.present? && !suggested.casecmp?(category.name)
        "user"
      elsif %w[ai rule].include?(candidate.classification_source.to_s)
        candidate.classification_source
      else
        return
      end

    ActivityClassification.record!(user: current_user, name: description, category: category, source: source)
  rescue StandardError => e
    Rails.logger.warn("[expense_playground] classification recording failed: #{e.class}: #{e.message}")
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
