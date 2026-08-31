# frozen_string_literal: true

# FinancialSetupsController
# Serves the hybrid financial setup wizard: entry, per-step source selection
# (manual / import / skip), manual entry, file import with extraction review,
# final review, and completion. Persists progress so users can resume later.
class FinancialSetupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_setup

  # GET /financial_setup — entry screen or resume into the workflow.
  def show
    if @setup.completed?
      redirect_to financial_setup_done_path
      return
    end

    if @setup.resumable?
      redirect_to financial_setup_step_path(step: FinancialSetupWizard.step_keys[@setup.current_step])
      return
    end

    @steps = FinancialSetupWizard.steps
    render :entry
  end

  # GET /financial_setup/accounts|credit_cards|loans|review
  def step
    @step = FinancialSetupWizard.step(params[:step])
    return redirect_to financial_setup_path unless @step&.key

    @current_index = step_index(@step.key)
    @steps = FinancialSetupWizard.steps
    @step_key = @step.key.to_s

    if review_step?
      render :review
    else
      render :step
    end
  end

  # POST /financial_setup/select
  # Records the manual/import/skip choice for a step. Skip advances; manual and
  # import route to their dedicated sub-screens.
  def select
    step_key = params.require(:step)
    choice = params.require(:choice)

    unless FinancialSetupWizard.choice?(choice)
      redirect_to financial_setup_step_path(step: step_key), alert: t("wizard.select.invalid")
      return
    end

    @setup.set_choice(step_key, choice)
    @setup.save!

    case choice
    when "skip"
      advance_or_save(step_key)
    when "import"
      redirect_to financial_setup_upload_screen_path(step: step_key)
    when "manual"
      redirect_to financial_setup_manual_screen_path(step: step_key)
    end
  end

  # GET /financial_setup/step/:step/manual
  def manual
    @step = FinancialSetupWizard.step(params[:step])
    @step_key = @step.key.to_s
    @setup.set_choice(@step_key, "manual")
    @setup.save!
    @rows = @setup.draft_sources(@step_key)
    @rows = [ blank_row ] if @rows.empty?
    @steps = FinancialSetupWizard.steps
    render :manual
  end

  # POST /financial_setup/manual
  # Persists manually entered draft rows and advances.
  def save_manual
    step_key = params.require(:step)
    rows = clean_rows(params[:sources] || [])

    @setup.set_choice(step_key, "manual")
    @setup.replace_draft_sources(step_key, rows)
    advance_or_save(step_key)
  end

  # GET /financial_setup/step/:step/upload
  def upload
    @step = FinancialSetupWizard.step(params[:step])
    @step_key = @step.key.to_s
    @setup.set_choice(@step_key, "import")
    @setup.save!
    @steps = FinancialSetupWizard.steps
    render :upload
  end

  # POST /financial_setup/upload
  # Runs the import pipeline and stores the extraction for review.
  def process_upload
    step_key = params.require(:step)

    if params[:file].blank?
      flash.now[:alert] = t("wizard.upload.file_required")
      return render_upload_renderer(step_key)
    end

    pipeline = ImportPipeline.new(user: current_user)
    result = pipeline.call(file: params[:file], password: params[:password])

    if result.ok?
      @setup.set_choice(step_key, "import")
      @setup.replace_draft_sources(step_key, result.sources.map(&:to_h))
      @setup.set_import_state(step_key, {
        sources: result.sources.map(&:to_h),
        transactions: result.transactions,
        duplicates: duplicates_for(step_key, result.sources)
      })
      @setup.save!
      redirect_to financial_setup_import_review_path(step: step_key)
    else
      flash.now[:alert] = result.error
      render_upload_renderer(step_key)
    end
  end

  # GET /financial_setup/:step/import_review — review extracted + duplicate choices
  def import_review
    @step = FinancialSetupWizard.step(params[:step])
    @step_key = @step.key.to_s
    @import = @setup.import_state(@step_key)
    @transactions = @import["transactions"] || []
    @sources = @import["sources"] || []
    @duplicates = @import["duplicates"] || {}
    @categories = Category.for_user(current_user)
    @steps = FinancialSetupWizard.steps
    render :import_review
  end

  # POST /financial_setup/:step/import_confirm
  # Drops sources the user unchecked, merges inline edit fields, saves the
  # duplicate-resolution choices and advances from review.
  def import_confirm
    step_key = params.require(:step)
    import = @setup.import_state(step_key)
    sources = import["sources"] || []
    duplicates = import["duplicates"] || {}

    keep = params[:keep]
    merged_sources = []
    sources.each_with_index do |source, idx|
      next if keep.present? && keep[idx.to_s].blank?

      merged_sources << source.merge(edit_fields(idx))
    end

    choices = params[:duplicates] || {}
    resolved = duplicates.each_with_object({}) do |(id, entry), out|
      out[id.to_s] = choices.fetch(id.to_s, entry["choice"] || "create")
    end

    import["sources"] = merged_sources
    import["duplicates"] = resolved
    @setup.set_import_state(step_key, import)
    advance_or_save(step_key)
  end

  # POST /financial_setup/complete
  # Creates records from confirmed drafts, then marks the setup complete.
  def complete
    result = FinancialSetups::Completer.new(setup: @setup).call
    if result.ok?
      @setup.complete!
      redirect_to financial_setup_done_path
    else
      redirect_to financial_setup_step_path(step: :review), alert: result.errors.join(" ")
    end
  end

  # GET /financial_setup/done
  def done
    unless @setup.completed?
      redirect_to financial_setup_path
      return
    end
    @count = current_user.money_sources.count
    render :done
  end

  # POST /financial_setup/dismiss — exit without losing progress
  def dismiss
    @setup.dismiss!
    redirect_to dashboard_path, notice: t("wizard.dismissed")
  end

  private

  def set_setup
    @setup = current_user.financial_setups
                         .where(status: %w[in_progress dismissed completed])
                         .order(updated_at: :desc, id: :desc)
                         .first || current_user.financial_setups.create!(status: "in_progress")
  end

  def step_index(step_key)
    FinancialSetupWizard.step_keys.index(step_key.to_sym)
  end

  def review_step?
    @step.key == :review
  end

  def advance_or_save(step_key = nil)
    current_idx = step_key ? step_index(step_key) : @setup.current_step
    next_index = [ current_idx + 1, FinancialSetupWizard.step_keys.length - 1 ].min
    @setup.current_step = next_index
    @setup.save!
    redirect_to financial_setup_step_path(step: FinancialSetupWizard.step_keys[next_index])
  end

  def blank_row
    { "name" => "", "bank" => "", "starting_balance" => "" }
  end

  def clean_rows(rows)
    rows = rows.values if rows.respond_to?(:values)
    rows.filter_map do |row|
      row = row.permit(:name, :bank, :kind, :starting_balance, :balance,
                       :credit_limit, :interest_rate, :interest_rate_type,
                       :card_brand, :card_last_four, :principal_amount,
                       :outstanding_balance, :monthly_payment, :payment_frequency,
                       :statement_day)
      h = row.to_h
      next if Array(h).blank?

      h.transform_values { |v| v.is_a?(String) ? v.strip : v }
    end.compact
  end

  def duplicates_for(step_key, sources)
    detector = StatementDuplicateDetector.new(user: current_user)
    sources.each_with_object({}) do |source, out|
      existing = detector.duplicate_of?(source)
      key = FinancialSetupWizard.duplicate_key(source)
      out[key] = { "choice" => existing ? "update" : "create", "duplicate" => !existing.nil? }
    end
  end

  # Inline edit fields from the review screen, as a string-keyed hash. Blank
  # fields are dropped so a cleared input removes the stored value.
  def edit_fields(idx)
    raw = params[:sources] && params[:sources][idx.to_s]
    return {} if raw.blank?

    %w[name bank balance outstanding_balance credit_limit card_last_four
       interest_rate interest_rate_type monthly_payment kind identifier]
      .to_h { |key| [ key, raw[key].to_s.strip ] }
      .compact_blank
  end

  def render_upload_renderer(step_key)    @step = FinancialSetupWizard.step(step_key)
    @step_key = step_key.to_s
    @steps = FinancialSetupWizard.steps
    render :upload
  end
end
