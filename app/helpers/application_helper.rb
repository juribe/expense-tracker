module ApplicationHelper
  CATEGORY_COLORS = %w[primary success danger warning info secondary dark].freeze

  def category_badge(category)
    color = CATEGORY_COLORS[(category.id || 0) % CATEGORY_COLORS.length]
    tag.span(category.name, class: "badge bg-#{color}")
  end

  def active_class(controller)
    controller_name == controller ? "active" : ""
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
end
