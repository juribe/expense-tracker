# frozen_string_literal: true

class MoneySourcesController < ApplicationController
  include MoneySourceShowContext

  before_action :authenticate_user!
  before_action :set_money_source, only: [ :show, :edit, :update, :destroy, :reset_adjustment ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  FILTERS = {
    "cash" => %w[cash wallet account debit_card],
    "pockets" => %w[pocket],
    "credit_cards" => %w[credit_card],
    "loans" => %w[loan]
  }.freeze

  # Each filter renders a different template using different associations;
  # preloading only what the rendered partial touches keeps Bullet quiet for
  # both N+1 (USE) and unused eager loading (AVOID) per page.
  INDEX_INCLUDES = {
    "cash" => %i[parent children recognition_identifiers],
    "pockets" => %i[],
    "credit_cards" => %i[credit_account],
    "loans" => %i[credit_account]
  }.freeze

  # GET /money_sources
  #
  # The general "all sources" index no longer exists: every card belongs to
  # exactly one section. A missing or unknown type goes to the default
  # accounts/cash section.
  def index
    unless FILTERS.key?(params[:type])
      redirect_to money_sources_cash_path and return
    end
    @filter = params[:type]
    scope = current_user.money_sources
    # Pockets touch no associations; includes() without arguments would raise.
    if INDEX_INCLUDES[@filter].present?
      scope = scope.includes(*INDEX_INCLUDES[@filter])
    end

    scope = scope.where(kind: FILTERS[@filter])

    @money_sources = scope.order(:kind, :name)
    @counts = FILTERS.each_with_object({}) do |(key, kinds), out|
      out[key] = current_user.money_sources.where(kind: kinds).count
    end
    @setup = current_user.financial_setups
                         .where(status: %w[in_progress dismissed])
                         .order(updated_at: :desc, id: :desc)
                         .first

    render index_template
  end

  # GET /money_sources/1
  def show
    load_payment_context if @money_source.debt?
    load_pocket_context if @money_source.pocket?
    @active_tab = "resumen"
  end

  # GET /money_sources/recognition
  #
  # Sources are GROUPED by their financial institution (the attached entity,
  # or the folded legacy bank text). Each group shows one bank-level
  # configuration (senders + subject patterns — the SEED source carries the
  # confirmed values and the whole group shares them) plus the per-source
  # rows whose drawer edits only the product-level keywords/last-four.
  def recognition
    sources = current_user.money_sources
                          .payment_sources
                          .includes(:recognition_identifiers, recognition: :recognition_identifiers)
                          .order(:kind, :name)
    # Children are loaded per KIND, only where the page reads them: the
    # identifiers cell shows each source's last four. Cards that carry their
    # own denormalized identifier never need the child; blank ones resolve it
    # from their credit_account, fetched here in a single query instead of an
    # eager include (which Bullet would flag as unused for identified cards).
    @recognition_last_fours = if sources.where(kind: "credit_card").exists?
      CreditAccount.where(money_source_id: sources.by_kind("credit_card").select { |source| source.identifier.blank? })
                   .index_by(&:money_source_id)
                   .transform_values { |account| MoneySource.last_four_from(account.card_last_four) }
    end
    @bank_groups = build_bank_groups(sources)
    @wizard = SourceRecognition::BankSetupWizard.new(@bank_groups) if params[:wizard].present?

    # The Gmail criteria card doubles as a manual editor: it renders whenever
    # there is an ACTIVE connection — even before any scan ran — prefilled
    # with the saved search_config plus (when available) the scan suggestions.
    @gmail_connection = current_user.gmail_connections.order(:created_at, :id).last

    if params[:edit].present? || params[:bank_edit].present?
      group = @bank_groups.find { |element| element[:key] == params[:bank_edit] }
      @bank_editing = params[:bank_edit].present? && group.present?
      @editing = group&.dig(:seed) || current_user.money_sources.find(params[:edit]) # product drawer otherwise
      engine = SourceRecognition::SuggestionEngine.new(
        source: @editing,
        # BANK drawer: the members' pending bank-level suggestions are
        # reviewed here so every card of the group stops showing them.
        group_members: @bank_editing ? (group[:members] - [ @editing ]) : []
      )
      @suggestions = engine.call

      # The engine's own suggestions persist at display time: from then on
      # the group card counts every pending value — gmail-discovered AND
      # own-computed — until it is applied or dismissed.
      persisted = engine.persist!
      group = @bank_groups.find { |element| Array(element[:members]).include?(@editing) }
      group[:pending] += persisted if group && persisted.positive?
    end
  end

  # POST /money_sources/:id/reset_adjustment
  #
  # Undoes the manual "Ajustar saldo" correction from the Día de Cuadre
  # dashboard: balance_offset goes back to zero (the balance returns to what
  # its transactions explain) and the trace is cleared. The cuadre state is
  # invalidated by the model's invalidation hook on update.
  def reset_adjustment
    @money_source.update!(balance_offset: 0, balance_offset_note: nil, balance_offset_at: nil)
    BalanceAdjustment.where(money_source_id: @money_source.id).delete_all
    redirect_to money_source_path(@money_source), notice: t("money_sources.flashes.adjustment_reset")
  end

  # PATCH /money_sources/recognition/:money_source_id
  #
  # The form submits the CONFIRMED chips per section. Persisted suggestions
  # the user accepted are promoted to confirmed (replace_identifiers handles
  # that without duplicates); suggestions explicitly dismissed with their ×
  # button arrive in `dismissed` and are deleted. Untouched suggestions are
  # preserved for a later review.
  #
  # Section ABSENCE means "leave that section as-is": the per-source drawer
  # posts only keywords, the bank-level drawer (seed source) posts only
  # senders/subject patterns. replace_identifiers replaces exactly the kinds
  # it receives.
  def update_recognition
    # Only payment sources may hold recognition (the model validates it too);
    # scoping the lookup makes non-payment sources 404 instead of failing on
    # the validation after ensure_recognition's save!.
    source = current_user.money_sources.payment_sources.find(params[:money_source_id])
    values = {}
    values[:keyword] = Array(params[:keywords]) if params.key?(:keywords)
    if params.key?(:senders)
      senders, domains = classify_senders(Array(params[:senders]))
      values[:sender] = senders
      values[:domain] = domains
    end
    if params.key?(:subjects)
      subjects, headers = classify_subjects(Array(params[:subjects]))
      values[:subject] = subjects
      values[:header] = headers
    end

    # Nothing submitted at all (a pure dismissal submit): don't create a
    # recognition record just to delete suggestions from it.
    recognition = values.empty? ? source.recognition : source.ensure_recognition

    if recognition
      ActiveRecord::Base.transaction do
        recognition.replace_identifiers(**values)
        recognition.dismiss_suggestions!(dismissed_suggestions)
        # Nothing at all left (confirmed or suggested) → drop the record so
        # the source flips to "Sin configurar".
        recognition.reload.destroy if recognition.recognition_identifiers.empty?
      end

      # Bank-drawer review (senders/subjects submitted): the siblings no
      # longer keep their own pending copies — values the seed now CONFIRMS
      # are satisfied at group level, and explicitly dismissed values are
      # deleted from every member of the group.
      if params.key?(:senders) || params.key?(:subjects)
        sweep_group_bank_suggestions(source, values)
      end

      # Feed the now-confirmed values back into the Gmail search config so the
      # next sync queries the confirmed bank senders/domains/subjects.
      SourceRecognition::ApplyToSearchConfig.call(user: current_user)
    end

    # Back to the BASE recognition URL: the drawer URL carries ?edit=/?bank_edit=
    # params, so redirecting to the referer would reopen the just-saved drawer.
    respond_to do |format|
      format.html { redirect_to money_sources_recognition_path, notice: t("money_sources.recognition.saved") }
      # The bank wizard saves one bank at a time without leaving the modal.
      # It receives the persisted state so it can show the correct status.
      format.json { render json: recognition_payload(source) }
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html do
        redirect_to money_sources_recognition_path,
                    alert: e.record.errors.full_messages.to_sentence
      end
      format.json do
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordNotUnique
    message = t("money_sources.recognition.wizard.save_error")
    respond_to do |format|
      format.html { redirect_to money_sources_recognition_path, alert: message }
      format.json { render json: { errors: [ message ] }, status: :unprocessable_entity }
    end
  end

  # Removes the members' bank-level SUGGESTED rows that the just-reviewed
  # bank config settles: any (kind, value) now confirmed on the seed, and any
  # value explicitly dismissed. Product keywords are never touched.
  def sweep_group_bank_suggestions(seed, submitted_values)
    group_key = group_key_for_source(seed)
    members = current_user.money_sources
                          .payment_sources
                          .includes(recognition: :recognition_identifiers)
                          .select { |candidate| group_key_for_source(candidate) == group_key && candidate.id != seed.id }
    return if members.empty?

    settled = submitted_values.filter_map do |kind, values|
      values = Array(values).compact_blank
      next if kind == :keyword || values.empty?

      [ kind.to_s, values ]
    end

    dismissed_bank_values = dismissed_suggestions.flat_map do |section, values|
      MoneySourceRecognition.section_kinds(section.to_s)
                            .reject { |kind| kind == "keyword" }
                            .product(Array(values).compact_blank)
    end

    members.each do |member|
      recognition_record = member.recognition
      next unless recognition_record

      stale = recognition_record.recognition_identifiers.suggested
                                .reject(&:keyword?)
                                .select do |identifier|
        settled.any? { |(kind, values)| kind == identifier.kind && values.include?(identifier.value) } ||
          dismissed_bank_values.include?([ identifier.kind, identifier.value ])
      end
      next if stale.empty?

      stale.each(&:destroy!)
      recognition_record.reload
      recognition_record.destroy if recognition_record.recognition_identifiers.empty?
    end
  end

  # DELETE /money_sources/recognition/:money_source_id
  def destroy_recognition
    source = current_user.money_sources.payment_sources.find(params[:money_source_id])
    source.recognition&.destroy
    redirect_to money_sources_recognition_path, notice: t("money_sources.recognition.deleted")
  end

  # GET /money_sources/new
  def new
    @money_source = current_user.money_sources.build
    @money_source.kind = params[:kind] if params[:kind].in?(MoneySource::KINDS)
    @money_source.build_credit_account
  end

  # GET /money_sources/1/edit
  def edit
  end

  # POST /money_sources
  def create
    @money_source = current_user.money_sources.build(money_source_params.except(:institution_ref))
    @money_source.assign_institution_ref(money_source_params[:institution_ref])

    if @money_source.save
      redirect_to kind_index_path(@money_source), notice: t("money_sources.flashes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /money_sources/1
  def update
    @money_source.assign_attributes(money_source_params.except(:institution_ref))
    # "FinancialInstitution:12" / "CustomFinancialInstitution:3" / blank.
    # Ownership of a custom entity is re-checked by the model against the
    # source's user, so a forged reference never binds foreign data.
    @money_source.assign_institution_ref(money_source_params[:institution_ref])

    if @money_source.save
      redirect_to kind_index_path(@money_source), notice: t("money_sources.flashes.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /money_sources/1
  def destroy
    @money_source.destroy
    redirect_to kind_index_path(@money_source), notice: t("money_sources.flashes.deleted")
  end

  private

  # Maps the (already sanitized) filter to its concrete template. The case
  # keeps the value a literal so no request parameter ever selects a path.
  def index_template
    case @filter
    when "cash" then "index_cash"
    when "pockets" then "index_pockets"
    when "credit_cards" then "index_credit_cards"
    when "loans" then "index_loans"
    end
  end

  # Groups payment sources by their entity for the recognition page. The
  # attached polymorphic entity wins; unattached rows fall back to the folded
  # legacy bank token ("legacy:..."), and rows without any bank stay as
  # single-source groups. The SEED (earliest member) is the source whose
  # recognition record carries the group's bank-level configuration.
  #
  # CASH gets a special group: the money lives wherever the person keeps it,
  # so there is no bank behind it — the group renders without a "configure
  # bank" affordance and the rows only carry product keywords.
  def build_bank_groups(sources)
    groups = Hash.new { |hash, key| hash[key] = [] }
    sources.each { |source| groups[group_key_for_source(source)] << source }

    groups.values.map do |members|
      seed = members.min_by { |member| [ member.created_at, member.id ] }
      cash_only = members.all? { |source| source.kind == "cash" }
      {
        key: group_key_for_source(members.first),
        label: cash_only ? I18n.t("money_sources.recognition.cash_group")
                         : (members.first.institution_name.presence || I18n.t("money_sources.recognition.no_bank_group")),
        cash_only: cash_only,
        seed: seed,
        members: members.sort_by { |source| [ source.kind, source.name ] },
        pending: members.sum { |source| source.recognition_identifiers.count(&:suggested?) }
      }
    end.sort_by { |group| [ group_cash_or_unbanked?(group) ? 1 : 0, group[:label].to_s.downcase ] }
  end

  def group_cash_or_unbanked?(group)
    group[:cash_only] || group[:key].to_s.starts_with?("legacy:", "source:")
  end

  def group_key_for_source(source)
    SourceRecognition::BankGrouping.key(source)
  end

  # The section redirect after create/update/destroy mirrors the helper used
  # by the views, so back links and post-action redirects always land on the
  # same section.
  def kind_index_path(source)
    helpers.money_sources_section_path(source)
  end

  # `dismissed` arrives as { "keywords" => [...], "senders" => [...],
  # "subjects" => [...] } from JS-added hidden inputs on the recognition form.
  def dismissed_suggestions
    raw = params[:dismissed]
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : {}
  end

  # Persisted bank-level state returned to the wizard after a JSON save.
  def recognition_payload(source)
    source.reload
    wizard = SourceRecognition::BankSetupWizard
    {
      configured: wizard.bank_configured?(source),
      senders: wizard.confirmed_values(source, %w[sender domain]),
      subjects: wizard.confirmed_values(source, %w[subject header])
    }
  end

  # The senders section mixes real addresses (sender) and bare domains
  # (domain) — delegated to SourceRecognition::ValueClassifier.
  def classify_senders(list)
    SourceRecognition::ValueClassifier.senders(list)
  end

  # The subjects section mixes subject text (subject) and RFC header patterns
  # like "From: ..." (header) — delegated to SourceRecognition::ValueClassifier.
  def classify_subjects(list)
    SourceRecognition::ValueClassifier.subjects(list)
  end

  def set_money_source
    @money_source = current_user.money_sources.find(params[:id])
  end

  def money_source_params
    permitted = [ :name, :kind, :sub_kind, :bank, :parent_id, :starting_balance, :active, :identifier,
                  :institution_ref ]

    if params.dig(:money_source, :kind).to_s.in?(%w[credit_card loan]) || @money_source&.debt?
      permitted << {
        credit_account_attributes: [ :id, :credit_limit, :interest_rate, :interest_rate_type,
                                     :card_brand, :card_last_four, :statement_day, :payment_due_day,
                                     :principal_amount, :outstanding_balance, :installment_amount,
                                     :installment_count, :installments_paid, :payment_frequency, :start_date, :end_date ]
      }
    end

    normalize_money_params!(params.require(:money_source)).permit(permitted)
  end

  # The forms render Colombian-formatted values ("29,3", "1.234.567,89"); the
  # browser mask submits machine format ("29.3"). Normalize both so decimal
  # columns cast cleanly instead of failing "is not a number".
  def normalize_money_params!(money_source)
    money_source[:starting_balance] = MoneyFormat.normalize(money_source[:starting_balance]) if money_source[:starting_balance].present?

    credit_account = money_source[:credit_account_attributes]
    return money_source unless credit_account

    %w[credit_limit interest_rate principal_amount outstanding_balance installment_amount].each do |field|
      credit_account[field] = MoneyFormat.normalize(credit_account[field]) if credit_account[field].present?
    end
    money_source
  end

  def not_found
    head :not_found
  end
end
