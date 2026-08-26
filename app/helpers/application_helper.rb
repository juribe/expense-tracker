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

    number_with_precision(value.to_d, precision: 2, strip_insignificant_zeros: true, delimiter: ",")
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
    else "circle"
    end
  end

  def source_kind_label(kind)
    kind.to_s.titleize
  end

  def identifier_display(ident)
    case ident.kind
    when "card_last_four"
      "**** #{ident.value}"
    when "bank_name"
      ident.value.titleize
    when "account_number"
      "****#{ident.value.last(4)}"
    else
      ident.value
    end
  end
end
