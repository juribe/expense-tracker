module DashboardHelper
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::DateHelper

  DASHBOARD_CHART_COLORS = [ "#3d82f6", "#ff8b20", "#f1b500", "#16a76d", "#ad55ef", "#ec4899", "#06b6d4", "#6b7280" ].freeze

  def currency(amount)
    number_to_currency(amount)
  end

  def category_label(name, amount)
    "#{name} (#{currency(amount)})"
  end

  def format_date(date)
    l(date, format: :short)
  end

  # Empty-state copy for the category card, phrased for the resolved period
  # (financial cycle when the user configured paydays, calendar month otherwise).
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

  # Cycle balance: income minus expenses, always signed so the direction is
  # readable without relying on color alone.
  def dashboard_signed_currency(amount)
    value = amount.to_d
    formatted = number_to_currency(value.abs)
    value.negative? ? "-#{formatted}" : "+#{formatted}"
  end

  def dashboard_balance_class(amount)
    amount.to_d.negative? ? "is-negative" : "is-positive"
  end

  # Selector options for the dashboard period: pay cycles when configured,
  # calendar months otherwise. Includes the selected period even when it is
  # older than the visible history.
  def dashboard_period_filter(user:, cycle:, month:)
    if cycle
      cycles = (0..11).map { |offset| PayCycle.containing(user, Date.current - offset.months) }
      cycles << PayCycle.containing(user, Date.current + 1.month)
      cycles << cycle
      options = cycles.uniq(&:starts).sort_by(&:starts).reverse
                     .map { |item| [ "#{item.label} · #{item.range_label}", item.starts.iso8601 ] }

      { param: :cycle, selected: cycle.starts.iso8601, options: options }
    else
      month ||= Date.current
      months = (0..11).map { |offset| Date.current.beginning_of_month - offset.months }
      months << month
      options = months.uniq.sort.reverse.map { |item| [ l(item, format: :month_year), item.strftime("%Y-%m") ] }

      { param: :month, selected: month.strftime("%Y-%m"), options: options }
    end
  end

  # Aggregated budget card: the sum of the user's category targets against
  # their recorded spending for the resolved period.
  def dashboard_budget_summary(budgets, period, spent_by_category: nil)
    total = budgets.sum { |budget| budget.amount_for(period).to_d }
    spent =
      if spent_by_category
        budgets.sum { |budget| spent_by_category[budget.category_id].to_d }
      else
        budgets.sum { |budget| budget.spent_for(period).to_d }
      end
    percentage = total.positive? ? spent / total * 100 : 0.0
    status =
      if percentage > 100
        :over_budget
      elsif percentage >= Budget::NEAR_LIMIT_PERCENT
        :near_limit
      else
        :on_track
      end

    {
      total: total,
      spent: spent,
      remaining: [ total - spent, 0 ].max,
      percentage: percentage,
      status: status
    }
  end

  def dashboard_budget_bar_class(status)
    case status.to_sym
    when :over_budget then "dash-budget-bar--over"
    when :near_limit then "dash-budget-bar--warning"
    else "dash-budget-bar--normal"
    end
  end

  # Money source label for the recent movements table. A missing source is
  # shown as an em dash instead of inventing a default account.
  def dashboard_money_source_badge(source)
    return tag.span("—", class: "dash-source-empty") if source.nil?

    tag.span(class: "dash-source-pill") do
      safe_join([
                  tag.i(nil, class: "ti ti-#{source_kind_icon(source.kind)}", "aria-hidden": true),
                  source.display_name
                ])
    end
  end

  def dashboard_payment_status_class(status)
    "dash-payment-status dash-payment-status--#{status}"
  end

  def dashboard_payment_status_label(status)
    t("dashboard.payment_status.#{status}")
  end

  def dashboard_payment_row_class(status)
    status.to_sym == :overdue ? "dash-payment dash-payment--overdue" : "dash-payment"
  end

  def dashboard_payment_date_label(payment)
    date = payment[:next_date]
    days = (date - Date.current).to_i
    relative =
      case payment[:status].to_sym
      when :paid then t("dashboard.payment_relative.paid", default: "Pagado")
      when :overdue then t("dashboard.payment_relative.overdue", days: days.abs, default: "Vencido hace %{days} días")
      else
        if days.zero?
          t("dashboard.payment_relative.today", default: "Hoy")
        else
          t("dashboard.payment_relative.pending", days: days, default: "En %{days} días")
        end
      end

    "#{l(date, format: '%e %b').squeeze(' ')} · #{relative}"
  end

  # Existing destinations, keeping the resolved financial cycle when possible.
  def dashboard_analysis_path
    monthly_report_path(PayCycle.period_for(current_user, @span.first).first)
  end

  def dashboard_budget_path
    @cycle ? budgets_path(cycle: @cycle.starts.iso8601) : budgets_path(month: @budget_period.strftime("%Y-%m"))
  end

  def dashboard_category_analysis_path
    reports_by_category_path(period: "custom", start_date: @span.first.iso8601, end_date: @span.last.iso8601)
  end

  def dashboard_upcoming_payments_path
    options = { status: "pending" }
    options[:period] = @cycle.starts.iso8601 if @cycle
    monthly_expenses_path(options)
  end

  def dashboard_expenses_path
    expenses_path(start_date: @span.first.iso8601, end_date: @span.last.iso8601)
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

  def onboarding_step_path(step)
    case step
    when "initial" then financial_setup_path
    when "gmail" then gmail_connection_path
    when "whatsapp" then whatsapp_settings_path
    end
  end

  def onboarding_step_icon(step)
    case step
    when "initial" then "ti-building-bank"
    when "gmail" then "ti-mail"
    when "whatsapp" then "ti-brand-whatsapp"
    end
  end
end
