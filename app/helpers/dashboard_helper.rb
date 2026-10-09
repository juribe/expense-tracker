module DashboardHelper
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::DateHelper

  DASHBOARD_CHART_COLORS = [ "#3b82f6", "#f97316", "#eab308", "#16a34a", "#a855f7", "#ec4899", "#06b6d4", "#6b7280" ].freeze

  def currency(amount)
    number_to_currency(amount)
  end

  def category_label(name, amount)
    "#{name} (#{currency(amount)})"
  end

  def format_date(date)
    l(date, format: :short)
  end

  # The expenses card speaks in financial cycles when the user configured
  # paydays; the calendar month otherwise (the card's data already follows
  # the resolved period).
  def dashboard_expenses_title(cycle)
    cycle ? t("dashboard.expenses_this_cycle", default: "Gastos de este ciclo") : t("dashboard.expenses_this_month", default: "Gastos de este mes")
  end

  def dashboard_no_expenses_label(cycle)
    cycle ? t("dashboard.no_expenses_this_cycle", default: "No hay gastos este ciclo") : t("dashboard.no_expenses_this_month", default: "No hay gastos este mes")
  end

  # Signed delta chip: "↑ +8.4%". `good_direction: :down` paints a decrease
  # green (spending less than before is good); :up paints an increase green.
  def dashboard_delta_badge(pct, good_direction: :up)
    return content_tag(:span, "—", class: "small text-muted") if pct.nil?

    improved = good_direction == :down ? pct.negative? : pct.positive?
    arrow = pct >= 0 ? "ti-arrow-up-right" : "ti-arrow-down-right"
    content_tag(:span, class: class_names("delta-badge", "delta-badge-success": improved, "delta-badge-danger": !improved)) do
      content_tag(:i, "", class: "ti #{arrow}") + " " + dashboard_signed_pct(pct)
    end
  end

  def dashboard_signed_pct(pct)
    "#{pct >= 0 ? '+' : ''}#{number_with_precision(pct, precision: 1, delimiter: '.')}%"
  end

  def dashboard_span_label(span)
    "#{l(span.first, format: '%e %b %Y').squeeze(' ')} – #{l(span.last, format: '%e %b %Y').squeeze(' ')}"
  end

  # Prev/next navigation for the resolved period: the previous/next cycle in
  # cycle mode (?cycle=anchor) or the adjacent calendar month otherwise.
  def dashboard_period_nav_path(direction)
    if @cycle
      anchor = direction == :prev ? @cycle.starts - 1.day : @cycle.ends + 1.day
      dashboard_path(cycle: anchor.iso8601)
    else
      month = direction == :prev ? @budget_period.prev_month : @budget_period.next_month
      dashboard_path(month: month.strftime("%Y-%m"))
    end
  end

  def dashboard_category_palette(count)
    DASHBOARD_CHART_COLORS.first(count)
  end
end