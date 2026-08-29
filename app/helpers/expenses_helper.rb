module ExpensesHelper
  SORTABLE_COLUMNS = %w[date description category amount].freeze
  DEFAULT_SORT_DIR = { "date" => "desc", "amount" => "desc" }.freeze
  PAGINATION_WINDOW = 2

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
             current_dir == "asc" ? "bi-caret-up-fill" : "bi-caret-down-fill"
    else
             "bi-chevron-expand"
    end

    attrs = { scope: "col", class: ("text-end" if column == "amount") }
    attrs["aria-sort"] = aria_sort if aria_sort

    content_tag(:th, attrs) do
      link_to expenses_path(sort_params.merge(sort: column, dir: dir)),
              class: "sort-btn#{' active' if active}",
              data: { testid: "sort-#{column}" } do
        concat label
        concat content_tag(:i, "", class: "bi #{icon} ms-1", "aria-hidden": "true")
      end
    end
  end

  # Bootstrap pagination; returns nil when there is only one page.
  def pagination_nav(current_page:, total_pages:)
    return if total_pages <= 1

    content_tag(:nav, "aria-label": t("expenses.pagination_aria"), data: { testid: "pagination" }) do
      content_tag(:ul, class: "pagination justify-content-center mb-0") do
        concat pagination_item(
          link_to(t("common.previous"), expenses_path(page_params.merge(page: current_page - 1))),
          item_class: "page-item#{' disabled' if current_page == 1}",
          active: false
        )
        pagination_page_links(current_page, total_pages).each do |item|
          concat item
        end
        concat pagination_item(
          link_to(t("common.next"), expenses_path(page_params.merge(page: current_page + 1))),
          item_class: "page-item#{' disabled' if current_page == total_pages}",
          active: false
        )
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

  private

  def pagination_item(content, item_class:, active:)
    content_tag(:li, class: item_class + (active ? " active" : "")) do
      content
    end
  end

  def pagination_page_links(current_page, total_pages)
    pages = pagination_window(current_page, total_pages)
    items = []
    pages.each do |page|
      items << if page == :ellipsis
                 content_tag(:li, content_tag(:span, "…", class: "page-link"), class: "page-item disabled")
      else
                 pagination_item(
                   link_to(page.to_s, expenses_path(page_params.merge(page: page))),
                   item_class: "page-item#{' active' if page == current_page}",
                   active: page == current_page
                 )
      end
    end
    items
  end

  def pagination_window(current_page, total_pages)
    return (1..total_pages).to_a if total_pages <= (PAGINATION_WINDOW * 2) + 1

    start_page = [ current_page - PAGINATION_WINDOW, 1 ].max
    end_page = [ current_page + PAGINATION_WINDOW, total_pages ].min
    window = (start_page..end_page).to_a
    window.unshift(1) unless window.include?(1)
    window.push(total_pages) unless window.include?(total_pages)
    result = []
    window.each_with_index do |page, index|
      if index.positive? && page - window[index - 1] > 1
        result << :ellipsis
      end
      result << page
    end
    result
  end
end
