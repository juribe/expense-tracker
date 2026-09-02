module ApplicationHelper
  CATEGORY_COLORS = %w[primary success danger warning info secondary dark].freeze

  def category_badge(category)
    color = CATEGORY_COLORS[(category.id || 0) % CATEGORY_COLORS.length]
    tag.span(category.name, class: "badge bg-#{color}")
  end

  def active_class(controller)
    controller_name == controller ? "active" : ""
  end

  def money_source_filter_active?(filter)
    @filter == filter ? "active" : ""
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
    when "account" then "bank"
    when "debit_card" then "credit-card"
    when "credit_card" then "credit-card-2-front"
    when "cash" then "cash"
    when "wallet" then "wallet2"
    when "loan" then "cash-coin"
    else "circle"
    end
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
    t("kinds.#{kind.to_s}", default: kind.to_s.titleize)
  end

  def source_kind_options
    MoneySource::KINDS.map { |kind| [ source_kind_label(kind), kind ] }
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
    revolving: { icon: "arrow-repeat", accent: "accent-teal" },
    mortgage: { icon: "house", accent: "accent-purple" },
    vehicle: { icon: "car-front", accent: "accent-amber" },
    education: { icon: "mortarboard", accent: "accent-blue" },
    personal: { icon: "wallet2", accent: "accent-rose" },
    business: { icon: "briefcase", accent: "accent-blueviolet" }
  }.freeze

  def loan_identity(loan)
    return { icon: "cash-coin", accent: "accent-slate" } unless loan.is_a?(MoneySource)

    name = [ loan.name, loan.bank ].compact.join(" ").downcase
    key =
      if name.match?(/rotativo|revolving|sobregiro|credit.?card/)
        :revolving
      elsif name.match?(/hipotec|mortgage|vivienda|house/)
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

  # Best-effort next payment date for a loan card. Prefers a scheduled
  # recurring template (payment day); otherwise derives a date from the loan's
  # start date and payment frequency. Returns nil when it cannot be known, so
  # the view shows "Sin fecha" rather than a fabricated value.
  def next_payment_date(loan)
    return nil unless loan.is_a?(MoneySource) && loan.loan?

    if (rt = loan.recurring_templates.active.order(:payment_day).first) && rt.payment_day
      return next_day_of_month(rt.payment_day)
    end

    derive_loan_payment_date(loan)
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
      value: "manual", icon: "pencil-square", icon_color: "text-primary",
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
        value: "skip", icon: "check2-circle", icon_color: "text-primary",
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

  # --- private helpers for the loans dashboard ---

  def next_day_of_month(day)
    today = Date.current
    candidate = Date.new(today.year, today.month, day.to_i)
    candidate = candidate.next_month if candidate < today
    candidate
  rescue ArgumentError, TypeError
    nil
  end

  PERIOD_ADVANCE = { "weekly" => 7, "biweekly" => 14, "monthly" => 1.month, "quarterly" => 3.months }.freeze

  def derive_loan_payment_date(loan)
    return nil if loan.start_date.blank? || loan.payment_frequency.blank?

    period = PERIOD_ADVANCE[loan.payment_frequency]
    return nil if period.nil?

    paid = loan.credit_account&.installments_paid.to_i
    current = advance_period(loan.start_date, period, paid)
    current = current + period if current < Date.current
    current
  end

  def advance_period(date, period, count)
    date + (period * count)
  end
end
