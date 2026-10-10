module ApplicationHelper
  CATEGORY_COLORS = %w[primary success danger warning info secondary dark].freeze

  def category_badge(category)
    return tag.span(t("common.uncategorized", default: "Sin categoría"), class: "badge bg-light text-dark border") if category.nil?

    color = CATEGORY_COLORS[(category.id || 0) % CATEGORY_COLORS.length]
    tag.span(category.name, class: "badge bg-#{color}")
  end

  # Money source with its kind icon; em dash placeholder when unset so table
  # cells never look broken.
  def money_source_badge(source)
    return tag.span("—", class: "text-muted") if source.nil?

    tag.span(class: "badge bg-light text-dark border text-nowrap") do
      safe_join([
                  tag.i(nil, class: "ti ti-#{source_kind_icon(source.kind)} me-1"),
                  source.display_name
                ])
    end
  end

  # The user's expense-type categories as [name, id] option pairs, used by the
  # statement import review and the payment block.
  def user_expense_category_options
    Category.for_user_and_type(current_user, "expense").pluck(:name, :id)
  end

  def active_class(controller)
    controller_name == controller ? "active" : ""
  end

  # Exact match on controller_path, needed where two controllers share a
  # controller_name (e.g. Reports::BudgetsController vs BudgetsController).
  def exact_active_class(path_name)
    controller_path == path_name ? "active" : ""
  end

  # Sidebar Reports submenu stays expanded on any reports page, including the
  # old monthly reports page and the drill-down.
  def reports_section_active?
    controller_path.to_s.start_with?("reports", "monthly_reports")
  end

  def money_source_filter_active?(filter)
    @filter == filter ? "active" : ""
  end

  # Contextual quick transfer actions for a money source card. The compact
  # form (TransfersController#quick_new) re-validates compatibility, so these
  # two must agree:
  #   cash          → deposit into an account + send to pocket
  #   account/card  → withdraw cash (only with a live cash source),
  #                   transfer, send to pocket
  #   credit card   → plain transfer only: cash advances and debt payments
  #                   run through their own flows
  # Inactive sources and pockets never offer quick actions.
  def quick_transfer_actions(source)
    return [] unless source.active? && source.payment_source?

    if source.cash?
      [ { mode: "transfer", icon: "building-bank", title: t("transfers.quick.deposit") },
        { mode: "pocket", icon: "pig-money", title: t("transfers.quick.pocket") } ]
    else
      actions = []
      actions << { mode: "withdraw", icon: "cash", title: t("transfers.quick.withdraw") } if quick_cash_destination && !source.debt?
      actions << { mode: "transfer", icon: "arrows-left-right", title: t("transfers.quick.transfer") }
      actions << { mode: "pocket", icon: "pig-money", title: t("transfers.quick.pocket") } unless source.debt?
      actions
    end
  end

  # The cash source quick transfers retire into: first active cash source by
  # creation order; nil when the user has none (no implicit creation).
  def quick_cash_destination
    current_user.money_sources.active.by_kind("cash").order(:id).first
  end

  def field_class(object, method)
    return "" unless object.errors.any?

    object.errors[method].any? ? "is-invalid" : "is-valid"
  end

  def field_error(object, method)
    object.errors[method].first
  end

  def money_field_value(value)
    return "" if value.blank?

    # Colombian format via the es locale: "." thousands, "," decimals
    # (67.429.112,92). number helpers read the format from I18n.
    number_with_precision(value.to_d, precision: 2, strip_insignificant_zeros: true)
  rescue NoMethodError, ArgumentError
    value.to_s
  end

  def source_kind_icon(kind)
    case kind
    when "account" then "building-bank"
    when "debit_card" then "credit-card"
    when "credit_card" then "credit-card"
    when "cash" then "cash"
    when "wallet" then "wallet"
    when "pocket" then "pig-money"
    when "loan" then "coin"
    else "circle"
    end
  end

  # The always-visible financial cycle indicator for the sidebar: the
  # configured financial cycle, or the current calendar month for users who
  # never changed the start day.
  # The always-visible financial cycle indicator for the sidebar: the
  # configured financial cycle, or the current calendar month for users who
  # never changed the start day. A rejected form submit (e.g. start day 30)
  # leaves an invalid value in memory, so the cycle lookup falls back to the
  # calendar month instead of raising while rendering.
  def financial_cycle_visible
    cycle = sidebar_cycle
    if cycle
      { heading: t("nav.current_cycle", default: "Ciclo financiero"), label: cycle.label, range: cycle.range_label }
    else
      { heading: t("nav.current_cycle", default: "Ciclo financiero"),
        label: I18n.l(Date.current, format: :month_year), range: nil }
    end
  end

  private

  def sidebar_cycle
    return nil unless current_user && Reports::Period.cycles_enabled?(current_user)

    PayCycle.current(current_user)
  rescue ArgumentError
    nil
  end

  def source_icon(source)
    case source
    when "text" then "message-circle"
    when "whatsapp" then "brand-whatsapp"
    when "email" then "mail"
    when "image" then "photo"
    when "ocr" then "scan"
    when "gmail" then "mail-opened"
    else "file"
    end
  end

  CANDIDATE_STATUS_CLASSES = {
    "needs_review" => "bg-warning text-dark",
    "ready" => "bg-success",
    "confirmed" => "bg-primary",
    "discarded" => "bg-secondary"
  }.freeze

  CANDIDATE_STATUS_LABELS = {
    "needs_review" => "Revisión pendiente",
    "ready" => "Listo",
    "confirmed" => "Confirmado",
    "discarded" => "Descartado"
  }.freeze

  def status_badge(status)
    css_class = CANDIDATE_STATUS_CLASSES[status] || "bg-secondary"
    label = CANDIDATE_STATUS_LABELS[status] || status.to_s.titleize
    tag.span(label, class: "badge #{css_class}")
  end

  # Returns the progress-bar color class for a utilization / repayment percent.
  def credit_utilization_class(pct)
    pct = pct.to_f
    if pct > 80
      "bg-danger"
    elsif pct >= 50
      "bg-warning"
    else
      "bg-success"
    end
  end

  def source_kind_label(kind)
    t("kinds.#{kind}", default: kind.to_s.titleize)
  end

  # Compact dd/mm/yyyy label for iso dates stored in credit projections.
  def date_label(value)
    return "—" if value.blank?

    I18n.l(Date.parse(value.to_s), format: :default)
  rescue Date::Error
    value.to_s
  end

  # "Febrero 2028" style payoff dates for projection summaries.
  def payoff_label(value)
    return "—" if value.blank?

    I18n.l(Date.parse(value.to_s), format: :month_year)
  rescue Date::Error
    value.to_s
  end

  # Label for a recurring template's select option in the "apply to recurring"
  # modal: the most identifying bits without taking too much width.
  def recurring_template_option_label(template)
    parts = [ template.description.presence, template.category&.name,
              number_to_currency(template.amount, unit: "") ]
    parts << "día #{template.payment_day}" if template.payment_day.present?
    parts.compact.join(" · ")
  end

  def source_kind_options
    MoneySource::KINDS.map { |kind| [ source_kind_label(kind), kind ] }
  end

  # ----- Financial goals / pockets -----

  GOAL_CATEGORY_EMOJIS = {
    "travel" => "✈️", "savings" => "💰", "emergency" => "🚨", "health" => "🏥",
    "education" => "🎓", "vehicle" => "🚗", "home" => "🏠", "holidays" => "🎄",
    "gifts" => "🎁", "taxes" => "🧾", "other" => "🎯"
  }.freeze

  def goal_category_emoji(category)
    GOAL_CATEGORY_EMOJIS.fetch(category, "🎯")
  end

  def goal_category_options
    Goal::CATEGORIES.map { |category| [ goal_category_label(category), category ] }
  end

  def goal_category_label(category)
    t("goals.categories.#{category}", default: category.to_s.titleize)
  end

  def goal_priority_options
    Goal::PRIORITIES.map { |name, value| [ t("goals.priorities.#{name}", default: name.to_s.titleize), value ] }
  end

  def goal_status_options
    Goal::STATUSES.map { |status| [ t("goals.statuses.#{status}", default: status.to_s.titleize), status ] }
  end

  # Grouped goal options for the transfer form's optional "assign to goal"
  # step: one optgroup per pocket, each option tagged with its pocket so JS
  # can filter them when the destiny pocket changes.
  def pocket_goal_groups(pockets)
    pockets.map do |pocket|
      [ pocket.name, pocket.goals.map { |goal| [ goal.name, goal.id, { "data-pocket-id" => pocket.id } ] } ]
    end
  end

  # Health badge for a goal card: derived state, colored per health.
  def goal_health_badge(goal)
    if goal.archived?
      return tag.span(t("goals.statuses.archived", default: "Archivada"), class: "badge bg-secondary")
    end

    labels = {
      completed: [ t("goals.health.completed", default: "Cumplida"), "bg-success" ],
      on_track: [ t("goals.health.on_track", default: "En rumbo"), "bg-success-subtle text-success" ],
      at_risk: [ t("goals.health.at_risk", default: "En riesgo"), "bg-warning text-dark" ],
      behind: [ t("goals.health.behind", default: "Atrás"), "bg-danger" ]
    }
    label, css_class = labels[goal.health]
    tag.span(label, class: "badge #{css_class}")
  end

  def goal_health_progress_class(goal)
    return "bg-secondary" if goal.archived?

    { completed: "bg-success", on_track: "bg-success", at_risk: "bg-warning", behind: "bg-danger" }[goal.health]
  end

  # Interest-rate type options with localized labels (reuses the money-sources
  # form's rate_type translations).
  def rate_type_options
    CreditAccount::INTEREST_RATE_TYPES.values.map do |type|
      [ t("money_sources.form.rate_type.#{type}", default: type.titleize), type ]
    end
  end

  # Available credit = credit limit minus the current debt (balance), floored at 0.
  def available_credit_for(row)
    limit = row["credit_limit"].to_d
    debt = row["balance"].to_d
    return 0 if limit <= 0

    [ limit - debt, 0 ].max
  end

  # Contextual icon + restrained accent for a loan card, inferred from the loan
  # name so each loan reads visually distinct without a data-model change.
  LOAN_ACCENTS = {
    revolving: { icon: "rotate", accent: "accent-teal" },
    mortgage: { icon: "home", accent: "accent-purple" },
    vehicle: { icon: "car", accent: "accent-amber" },
    education: { icon: "school", accent: "accent-blue" },
    personal: { icon: "wallet", accent: "accent-rose" },
    business: { icon: "briefcase", accent: "accent-blueviolet" }
  }.freeze

  def loan_identity(loan)
    return { icon: "coin", accent: "accent-slate" } unless loan.is_a?(MoneySource)

    name = [ loan.name, loan.bank ].compact.join(" ").downcase
    key =
      if name.match?(/rotativo|revolving|sobregiro|credit.?card/)
        :revolving
      elsif name.match?(/hipotec|mortgage|hogar|vivienda|house/)
        :mortgage
      elsif name.match?(/veh[ií]culo|vehicular|auto|car|moto/)
        :vehicle
      elsif name.match?(/educaci[oó]n|estudio|student|universit/)
        :education
      elsif name.match?(/libre|personal|consumo/)
        :personal
      elsif name.match?(/empresa|negocio|pyme|comercial|business/)
        :business
      else
        :revolving
      end
    LOAN_ACCENTS.fetch(key)
  end

  # Loan subtype options for the wizard's loan step and the money-source
  # form. Blank means "other/plain loan" (still a debt-payment target only).
  def loan_sub_kind_options
    [ [ t("money_sources.form.loan_kind.other", default: "Otro"), "" ] ] +
      MoneySource::SUB_KINDS.map { |k| [ source_sub_kind_label(k), k ] }
  end

  def source_sub_kind_label(sub_kind)
    t("kinds_sub.#{sub_kind}", default: sub_kind.titleize)
  end

  # Best-effort next payment date for a loan card, delegated to
  # Loans::NextPayment (recurring template first, then start-date derivation).
  def next_payment_date(loan)
    return nil unless loan.is_a?(MoneySource) && loan.loan?

    Loans::NextPayment.call(loan)
  end

  # Aggregates used by the loans dashboard summary card.
  def loan_summary(loans)
    loans = Array(loans)
    total_balance = loans.sum { |l| l.outstanding_balance.to_d }
    active_count = loans.count { |l| l.active? }
    remaining = loans.sum do |l|
      value = l.remaining_installments
      value.is_a?(Numeric) && value.positive? ? value : 0
    end
    next_30d = loans.sum { |l| l.active? && l.installment_amount.present? ? l.installment_amount.to_d : 0 }
    { total_balance: total_balance, active_count: active_count, remaining: remaining, next_30d: next_30d }
  end

  # Option hashes for the wizard's step-screen choice cards (rendered through
  # the _choice_card partial). Content and layout vary by step kind and by
  # whether the step already has sources added.
  def wizard_choice_cards(presenter, step)
    kind_label = t(step.label_key).downcase
    col_class = presenter.importable? ? "col-md-4" : "col-md-6"

    cards = [ {
      value: "manual", icon: "edit", icon_color: "text-primary",
      title: t("wizard.select.manual"),
      hint: t("wizard.select.manual_hint", kind: kind_label),
      col_class: col_class
    } ]

    if presenter.importable?
      cards << {
        value: "import", icon: "upload", icon_color: "text-primary",
        title: t("wizard.select.import"),
        hint: t("wizard.select.import_hint"),
        col_class: "col-md-4"
      }
    end

    if presenter.has_added?
      cards << {
        value: "skip", icon: "circle-check", icon_color: "text-primary",
        title: t("wizard.select.continue_title"),
        hint: t("wizard.select.continue_hint", count: presenter.added_count, kind: kind_label),
        col_class: col_class
      }
    else
      cards << {
        value: "skip", icon: "arrow-right-circle", icon_color: "text-muted",
        title: t("wizard.select.skip"),
        hint: t("wizard.select.skip_hint", kind: kind_label),
        col_class: col_class
      }
    end

    cards
  end

  def category_type_label(scope)
    case scope.to_s
    when "expense" then t("types.expense")
    when "income" then t("types.income")
    else t("types.all")
    end
  end

  def status_label(status)
    case status.to_s
    when "pending" then t("statuses.pending")
    when "completed" then t("statuses.completed")
    when "active" then t("statuses.active")
    when "inactive" then t("statuses.inactive")
    else t("statuses.inactive")
    end
  end

  def statuses_label(status)
    case status.to_s
    when "activated" then t("statuses.activated")
    when "deactivated" then t("statuses.deactivated")
    end
  end

  # True when the current user has finished the initial setup wizard, so the
  # sidebar can stop surfacing the setup entry point.
  def financial_setup_completed?
    return false unless respond_to?(:current_user) && current_user.present?

    current_user.financial_setups.exists?(status: "completed")
  end

  # Short caption explaining where a recognition suggestion came from.
  # s is a { value:, source: } hash where source is :gmail, :name,
  # :institution, :last_four or a sibling Money Source name.
  def suggestion_provenance(s)
    case s[:source]
    when :gmail
      t("money_sources.recognition.suggested_from_gmail")
    when :name
      t("money_sources.recognition.suggested_from_name")
    when :institution
      t("money_sources.recognition.suggested_from_institution")
    when :kind
      t("money_sources.recognition.suggested_from_kind")
    when :last_four
      t("money_sources.recognition.suggested_from_last_four")
    else
      t("money_sources.recognition.suggested_from_source", source: s[:source])
    end
  end

  # --- private helpers for the loans dashboard ---
end
