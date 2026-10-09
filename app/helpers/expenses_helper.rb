module ExpensesHelper
  SORTABLE_COLUMNS = %w[date description category amount].freeze
  DEFAULT_SORT_DIR = { "date" => "desc", "amount" => "desc" }.freeze

  # Builds a sortable table header button (<a>) that navigates with the
  # current filters and toggles asc/desc. First click on a new column uses
  # the column default (dates/amounts desc, text asc); second click toggles.
  def sortable_column_header(label, column, current_sort:, current_dir:)
    active = current_sort == column
    dir = if active
            current_dir == "asc" ? "desc" : "asc"
    else
            DEFAULT_SORT_DIR.fetch(column, "asc")
    end
    aria_sort = active ? (current_dir == "asc" ? "ascending" : "descending") : nil
    icon = if active
             current_dir == "asc" ? "ti-caret-up" : "ti-caret-down"
    else
             "ti-selector"
    end

    attrs = { scope: "col", class: ("text-end" if column == "amount") }
    attrs["aria-sort"] = aria_sort if aria_sort

    content_tag(:th, attrs) do
      link_to expenses_path(sort_params.merge(sort: column, dir: dir)),
              class: "sort-btn#{' active' if active}",
              data: { testid: "sort-#{column}" } do
        concat label
        concat content_tag(:i, "", class: "ti #{icon} ms-1", "aria-hidden": "true")
      end
    end
  end

  def filter_params
    {
      category_id: params[:category_id],
      start_date: params[:start_date],
      end_date: params[:end_date],
      min_amount: params[:min_amount],
      max_amount: params[:max_amount]
    }.compact_blank
  end

  def sort_params
    filter_params.slice(:category_id, :start_date, :end_date, :min_amount, :max_amount)
  end

  def page_params
    sort_params.merge(sort: params[:sort], dir: params[:dir]).compact_blank
  end

  # Full query state (filters + sort + page) used to preserve the current
  # view across row-level actions and delete redirects.
  def state_query
    page_params.merge(page: params[:page]).compact_blank
  end
end
