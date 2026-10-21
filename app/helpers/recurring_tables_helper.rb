# frozen_string_literal: true

# Shared by the recurring expense/income listings: clickable sort headers
# that merge with the current filters (status, category, search text).
module RecurringTablesHelper
  def recurring_sort_link(column, current_sort, direction, &)
    next_direction = current_sort == column && direction == "asc" ? "desc" : "asc"
    url = url_for(request.query_parameters.merge(sort: column, dir: next_direction))

    active = current_sort == column
    icon   = active ? (direction == "asc" ? "ti-arrow-up" : "ti-arrow-down") : "ti-arrows-sort"

    tag.a(href: url, class: "d-inline-flex align-items-center gap-1 text-decoration-none") do
      concat(capture(&))
      concat(icon_tag(icon, "fs-5 #{active ? '' : 'text-secondary'}"))
    end
  end

  def icon_tag(name, extra_classes = "")
    tag.i(nil, class: "ti #{name} #{extra_classes}".strip)
  end
end
