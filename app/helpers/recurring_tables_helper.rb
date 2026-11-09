# frozen_string_literal: true

# Shared by the recurring expense/income listings: clickable sort headers
# that merge with the current filters (status, category, search text).
module RecurringTablesHelper
  def recurring_sort_link(column, current_sort, direction, &)
    next_direction = current_sort == column && direction == "asc" ? "desc" : "asc"
    url = url_for(request.query_parameters.merge(sort: column, dir: next_direction))

    active = current_sort == column
    icon   = active ? (direction == "asc" ? "ti-arrow-up" : "ti-arrow-down") : "ti-arrows-sort"
    classes = "recurring-sort-link d-inline-flex align-items-center gap-1 text-decoration-none"
    classes += " active" if active

    tag.a(href: url,
          class: classes,
          data: { recurring_sort_column: column, recurring_sort_direction: next_direction }) do
      concat(capture(&))
      concat(icon_tag(icon, "fs-5 #{active ? '' : 'text-secondary'}"))
    end
  end

  def icon_tag(name, extra_classes = "")
    tag.i(nil, class: "ti #{name} #{extra_classes}".strip)
  end

  # Due date of a recurring template inside the listed period (a pay cycle or
  # a calendar month). Returns nil when the template has no payment day.
  def recurring_expected_date(template, period)
    RecurringExpenses::CycleSummary.expected_date(template, period)
  end

  def recurring_status_badge(status)
    label, icon, modifier =
      case status
      when :completed then [ t("statuses.completed"), "ti-circle-check", "completed" ]
      when :pending then [ t("statuses.pending"), "ti-clock", "pending" ]
      else [ t("statuses.inactive"), "ti-minus-circle", "inactive" ]
      end

    tag.span(class: "badge rounded-pill recurring-status recurring-status--#{modifier}") do
      safe_join([ tag.i(nil, class: "ti #{icon}", "aria-hidden": true), label ])
    end
  end
end
