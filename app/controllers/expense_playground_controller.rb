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

    result = Expenses::Processor.call(user: current_user, input: input, recording: Expenses::Processors::Recording.new)
    puts "[expense_playground] run result: ok=#{result.ok?} engine=#{result.engine} duration_ms=#{result.duration_ms} candidates=#{result.candidates&.as_json} errors=#{result.errors} warnings=#{result.warnings}"
    run_record = persist_run(input, result)

    candidates = result.candidates || []

    render json: {
      ok: result.ok?,
      run_id: run_record&.id,
      engine: result.engine,
      duration_ms: result.duration_ms,
      candidate: candidates.first&.as_json,
      candidates: candidates.map(&:as_json),
      errors: result.errors,
      warnings: result.warnings,
      steps: result.steps,
      evaluation: expected_params.present? && candidates.any? ? run_evaluation(candidates.first) : nil,
      evaluations: expected_params.present? ? candidates.map { |candidate| run_evaluation(candidate) } : nil
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

    summary = Ai::Metrics.summary(scope)

    render json: {
      summary: summary,
      performance: {
        average_latency_ms: summary[:average_latency_ms],
        p95_latency_ms: summary[:p95_latency_ms],
        average_tokens_per_second: summary[:average_tokens_per_second],
        latency_by_model: summary[:latency_by_model],
        slowest_model: summary[:slowest_model],
        slowest_model_latency_ms: summary[:slowest_model_latency_ms]
      },
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
          input_tokens: r.input_tokens,
          output_tokens: r.output_tokens,
          tokens_per_second: r.tokens_per_second,
          prompt: r.prompt,
          output: r.output,
          created_at: r.created_at.iso8601
        }
      end
    }
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
        source: candidate.source.presence || "playground_file",
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
    evaluation = ExpensePlayground::Evaluation.call(candidate: candidate, expected: expected_params)
    # `ok` mirrors `ok?` for the front-end (which reads a plain boolean).
    evaluation.merge(ok: evaluation[:ok?])
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
