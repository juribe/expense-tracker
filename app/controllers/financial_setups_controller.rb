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

      # Imported sources live only in the import state, accumulated across
      # multiple "import more" uploads. Never pull from draft_sources, which
      # holds manual entries — so switching to import only shows fresh imports.
      current_imports = Array(@setup.import_state(step_key)["sources"])
      new_sources = result.sources.map(&:to_h)

      # A step only accepts sources of its own kind. The AI may misclassify a
      # document (e.g. a credit-card statement uploaded in the loans step), and
      # the completer creates every source as the step's kind — keeping a
      # mismatched source would create a record with the wrong kind and junk
      # fields, so drop it and tell the user.
      step_kind = FinancialSetupWizard.step(step_key)&.kind
      matched_sources = result.sources
      if step_kind.present?
        new_sources, mismatched = new_sources.partition { |s| s["kind"] == step_kind }
        matched_sources = result.sources.select { |s| s.kind == step_kind }
        if mismatched.any?
          flash.now[:alert] = t("wizard.upload.ignored_kinds",
                                count: mismatched.size,
                                kind: t("wizard.steps.#{step_key}").downcase)
        end
      end

      imported = (current_imports + new_sources).uniq do |s|
        id = s["identifier"].to_s.gsub(/\D/, "")
        id.presence || "#{s["bank"]}-#{s["name"]}"
      end

      @setup.set_import_state(step_key, {
        sources: imported,
        transactions: result.transactions,
        duplicates: duplicates_for(step_key, matched_sources)
      })
      @setup.save!
      redirect_to financial_setup_import_review_path(step: step_key)
    else
      flash.now[:alert] = result.error
      render_upload_renderer(step_key)
    end
  end

  # GET /financial_setup/step/:step/edit_all — combined editor for the
  # whole "Added" list (manual + imported rows), each tagged with its origin.
  def edit_all
    @step = FinancialSetupWizard.step(params[:step])
    @step_key = @step.key.to_s
    @rows = combined_edit_rows(@step_key)
    @rows = [ blank_row.merge("origin" => "manual") ] if @rows.empty?
    @steps = FinancialSetupWizard.steps
    render :edit_all
  end

  # POST /financial_setup/save_edits — persists the combined editor, routing
  # each edited row back to the store it originally came from. Rows carry the
  # orig_key they were rendered with, so a cleared/edited identifier still
  # matches the stored row and unrendered fields are preserved.
  def save_edits
    step_key = params.require(:step)
    rows = clean_edit_rows(params[:sources] || [])

    manual_store = @setup.draft_sources(step_key)
    import_store = Array(@setup.import_state(step_key)["sources"])

    new_manual = []
    new_import = []
    rows.each do |row|
      origin = row.delete("origin")
      orig_key = row.delete("orig_key").presence
      finder = ->(entry) { find_stored_row(entry, orig_key, row) }

      if origin == "import"
        base = import_store.find(&finder)
        new_import << (base ? base.merge(row) : row)
      else
        base = manual_store.find(&finder)
        new_manual << (base ? base.merge(row) : row)
      end
    end

    @setup.replace_draft_sources(step_key, new_manual)
    import = @setup.import_state(step_key)
    import["sources"] = new_import
    @setup.set_import_state(step_key, import)
    @setup.save!
    redirect_to financial_setup_step_path(step: step_key), notice: t("wizard.select.edited")
  end

  def remove_source
    step_key = params.require(:step)
    idx = params.require(:idx).to_i

    manual = @setup.draft_sources(step_key)
    imported = Array(@setup.import_state(step_key)["sources"])

    # The step screen "Added" list is a combined summary (manual + import), so
    # idx points into that combined list. Resolve the target there, then remove
    # it from whichever store actually holds it — never cross-write the stores.
    combined = (manual + imported).uniq do |s|
      s["identifier"].presence || "#{s["bank"]}-#{s["name"]}"
    end
    target = combined[idx]
    if target.nil?
      return redirect_to financial_setup_step_path(step: step_key), alert: "Source not found"
    end

    key = ->(s) { s["identifier"].to_s.gsub(/\D/, "").presence || "#{s["bank"]}-#{s["name"]}" }
    manual.reject! { |s| key.call(s) == key.call(target) }
    imported.reject! { |s| key.call(s) == key.call(target) }

    @setup.replace_draft_sources(step_key, manual)
    @setup.set_import_state(step_key, @setup.import_state(step_key).merge("sources" => imported))
    @setup.save!

    redirect_to financial_setup_step_path(step: step_key), notice: "Source removed"
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

      merged_sources << source.merge(edit_fields(idx, source["kind"]))
    end

    choices = params[:duplicates] || {}
    resolved = duplicates.each_with_object({}) do |(id, entry), out|
      out[id.to_s] = choices.fetch(id.to_s, entry["choice"] || "create")
    end

    import["sources"] = merged_sources
    import["duplicates"] = resolved
    @setup.set_import_state(step_key, import)

    if params[:save_only]
      @setup.save!
      redirect_to financial_setup_step_path(step: step_key), notice: t("wizard.review_extract.saved")
    else
      advance_or_save(step_key)
    end
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

  # POST /financial_setup/reset — clear all wizard progress and start over
  def reset
    @setup.reset!
    redirect_to financial_setup_path, notice: t("wizard.reset.done")
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

  # Combined "Added" list for a step (manual + import), each row tagged with an
  # "origin" key so the combined editor can route edits back to its store, and
  # an "orig_key" frozen at render time so saving still matches the stored row
  # even when the user cleared or changed the identifier.
  def combined_edit_rows(step_key)
    manual_rows = @setup.draft_sources(step_key).map do |row|
      row.merge("origin" => "manual", "orig_key" => edit_key(row))
    end
    import_rows = Array(@setup.import_state(step_key)["sources"]).map do |row|
      row.merge("origin" => "import", "orig_key" => edit_key(row))
    end
    (manual_rows + import_rows).uniq { |row| edit_key(row) }
  end

  def edit_key(row)
    identifier = row["identifier"].to_s.gsub(/\D/, "")
    identifier.presence || "#{row["bank"]}-#{row["name"]}"
  end

  # Matches a stored row against an edited one: prefer the orig_key the editor
  # rendered (stable even if the identifier was cleared), fall back to the
  # row's current key.
  def find_stored_row(entry, orig_key, row)
    if orig_key.present?
      edit_key(entry) == orig_key
    else
      edit_key(entry) == edit_key(row)
    end
  end

  def clean_rows(rows)
    rows = rows.values if rows.respond_to?(:values)
    rows.filter_map do |row|
      row = row.permit(:name, :bank, :kind, :starting_balance, :balance,
                       :credit_limit, :interest_rate, :interest_rate_type,
                       :card_brand, :card_last_four, :identifier, :principal_amount,
                       :outstanding_balance, :monthly_payment, :payment_frequency,
                       :statement_day)
      h = row.to_h
      next if Array(h).blank?

      normalize_row_money(h)
    end.compact
  end

  # Same as clean_rows but keeps the origin tag used by the combined editor
  # (manual vs import) so each row can be routed back to its own store.
  def clean_edit_rows(rows)
    rows = rows.values if rows.respond_to?(:values)
    rows.filter_map do |row|
      row = row.permit(:origin, :orig_key, :name, :bank, :kind, :starting_balance, :balance,
                       :credit_limit, :interest_rate, :interest_rate_type,
                       :card_brand, :card_last_four, :identifier, :principal_amount,
                       :outstanding_balance, :monthly_payment, :payment_frequency,
                       :statement_day)
      h = row.to_h
      next if Array(h).blank?

      normalize_row_money(h)
    end.compact
  end

  def normalize_row_money(h)
    money_fields = %w[balance starting_balance credit_limit outstanding_balance monthly_payment principal_amount]
    h.each_with_object({}) do |(field, value), out|
      v = value.is_a?(String) ? value.strip : value
      v = normalize_money_string(v) if money_fields.include?(field) && v.is_a?(String)
      # Rates have no thousands separator: only the decimal comma flips.
      v = v.tr(",", ".") if field == "interest_rate" && v.is_a?(String)
      out[field] = v
    end
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
  def edit_fields(idx, kind = nil)
    raw = params[:sources] && params[:sources][idx.to_s]
    return {} if raw.blank?

    fields = %w[name bank balance outstanding_balance credit_limit card_last_four
                interest_rate interest_rate_type monthly_payment principal_amount kind identifier]
      .to_h do |key|
        value = raw[key].to_s.strip
        value = normalize_money_string(value) if %w[balance outstanding_balance credit_limit monthly_payment principal_amount].include?(key)
        value = value.tr(",", ".") if key == "interest_rate"
        [ key, value ]
      end
      .compact_blank

    # Derive last four digits from an edited card number when no last-four was
    # provided directly. Only for credit cards — loan contract numbers are not
    # card numbers.
    if kind == "credit_card" && fields["identifier"].present? && fields["card_last_four"].blank?
      last4 = fields["identifier"].scan(/\d/).join[-4..]
      fields["card_last_four"] = last4 if last4&.length == 4
    end

    fields
  end

  # Colombian rule: "." is the thousands separator and "," the decimal one
  # ("67.429.112,92"). Converts to the machine format ("67429112.92") so
  # decimal columns and BigDecimal parse the value correctly.
  def normalize_money_string(value)
    return value if value.blank?

    value.delete(".").tr(",", ".")
  end

  def render_upload_renderer(step_key)    @step = FinancialSetupWizard.step(step_key)
    @step_key = step_key.to_s
    @steps = FinancialSetupWizard.steps
    render :upload
  end
end
