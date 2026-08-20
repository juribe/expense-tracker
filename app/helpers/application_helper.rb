module ApplicationHelper
  CATEGORY_COLORS = %w[primary success danger warning info secondary dark].freeze

  def category_badge(category)
    color = CATEGORY_COLORS[(category.id || 0) % CATEGORY_COLORS.length]
    tag.span(category.name, class: "badge bg-#{color}")
  end

  def frequency_options
    %w[one_time weekly monthly yearly].map { |f| [f.humanize, f] }
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
end
