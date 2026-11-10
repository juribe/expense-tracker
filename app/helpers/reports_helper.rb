# frozen_string_literal: true

# ReportsHelper
# Presentation helpers for the Reports section.
#
# Methods: money_amount, delta_badge, progress_usage, available_cycle_*,
#          trend_* helpers for the spending-trend report
#
# Example: delta_badge(delta_pct, good_when_positive: false) # => "↑ 12.4% vs periodo anterior"
module ReportsHelper
  AVAILABLE_CYCLE_TONES = %w[purple blue orange green pink].freeze
  BUDGET_USAGE_WARNING_PERCENT = 75
  BUDGET_USAGE_CRITICAL_PERCENT = 90

  def money_amount(value)
    return content_tag(:span, "—", class: "text-muted") if value.blank?

    number_to_currency(value.to_d, precision: 0)
  end

  # Balance del ciclo: status, comparison, narrative and table presentation
  # helpers shared by the list and detail screens.
  def cycle_status_label(status)
    t("reports.cycle_balance.status_#{status}", default: status.to_s.humanize)
  end

  def cycle_status_class(status)
    "is-#{status.to_s.tr('_', '-')}"
  end

  def cycle_tone(amount)
    value = amount.to_d
    return :positive if value.positive?
    return :negative if value.negative?

    :neutral
  end

  def cycle_savings_label(rate)
    rate.nil? ? t("reports.cycle_balance.not_available", default: "N/A") : number_to_percentage(rate, precision: 1)
  end

  def cycle_date_range_label(starts, ends)
    start_format = starts.year == ends.year ? "%d de %B" : "%d de %B de %Y"
    "#{l(starts, format: start_format).downcase} – #{l(ends, format: '%d de %B de %Y').downcase}"
  end

  # "↑ +$1.000.000 (+12,4%) frente al ciclo anterior". A zero previous value
  # has no percentage base, so it says so instead of dividing by zero.
  def cycle_comparison_note(delta, good_direction: :up, same_elapsed_days: false, testid: nil)
    unless delta[:base_available]
      return content_tag(:span, t("reports.cycle_balance.no_comparison_base", default: "Sin base de comparación"),
                         class: "text-secondary", data: { testid: testid }.compact)
    end

    improved = good_direction == :down ? delta[:direction] == :down : delta[:direction] == :up
    tone = if delta[:direction] == :flat
      "is-neutral"
    elsif improved
      "is-positive"
    else
      "is-negative"
    end
    arrow = { up: "ti-arrow-up-right", down: "ti-arrow-down-right" }.fetch(delta[:direction], "ti-minus")
    context = same_elapsed_days ? t("reports.cycle_balance.vs_previous_partial", default: "frente al mismo tramo del ciclo anterior") :
                                  t("reports.cycle_balance.vs_previous", default: "frente al ciclo anterior")
    signed_amount = "#{delta[:amount].negative? ? '-' : '+'}#{number_to_currency(delta[:amount].abs, precision: 0)}"
    percentage = number_to_percentage(delta[:pct].abs, precision: 1)

    content_tag(:span, class: class_names("cycle-delta", tone),
                      data: { testid: testid }.compact) do
      safe_join([
        content_tag(:i, "", class: "ti #{arrow}", aria: { hidden: true }),
        "#{signed_amount} (#{percentage}) #{context}"
      ])
    end
  end

  def cycle_narrative(balance)
    return t("reports.cycle_balance.narrative_empty", default: "Este ciclo todavía no tiene movimientos registrados.") if balance[:movement_count].zero?

    if balance[:income_total].zero?
      t("reports.cycle_balance.narrative_no_income",
        default: "No registraste ingresos en este ciclo. Tus gastos reales fueron de %{amount}.",
        amount: money_amount(balance[:expense_total]))
    elsif balance[:net_total].positive?
      t("reports.cycle_balance.narrative_positive",
        default: "Durante este ciclo tus ingresos superaron tus gastos reales. Tu resultado neto fue de %{amount}.",
        amount: money_amount(balance[:net_total]))
    elsif balance[:net_total].negative?
      t("reports.cycle_balance.narrative_negative",
        default: "Durante este ciclo tus gastos superaron tus ingresos registrados. Tu resultado neto fue de %{amount}.",
        amount: money_amount(balance[:net_total]))
    else
      t("reports.cycle_balance.narrative_equal",
        default: "Durante este ciclo tus ingresos y gastos reales fueron iguales.")
    end
  end

  def cycle_transaction_type_label(transaction)
    transaction.kind == "income" ? t("types.income") : t("types.expense")
  end

  def cycle_transaction_type_class(transaction)
    transaction.kind == "income" ? "is-income" : "is-expense"
  end

  def cycle_transaction_date(transaction)
    l(transaction.date, format: "%d %b %Y").squeeze(" ")
  end

  def cycle_transaction_amount(transaction)
    amount = transaction.amount.to_d
    sign = amount.negative? ? "-" : "+"
    content_tag(:span, "#{sign}#{number_to_currency(amount.abs, precision: 0)}",
                class: amount.negative? ? "cycle-amount-expense" : "cycle-amount-income")
  end

  # Category icons are stored as full `ti-*` classes; legacy categories may
  # have none, so the report falls back to the generic tag icon.
  def budget_category_icon(icon)
    icon = icon.to_s.strip
    icon.match?(/\Ati-[a-z0-9-]+\z/) ? icon : "ti-tag"
  end

  # Budget consumption level used by the summary card, table bars and chart.
  # The thresholds are presentation rules for this report; the domain status
  # on Budget stays untouched.
  def budget_usage_level(pct)
    return :none if pct.nil?
    return :critical if pct.to_f >= BUDGET_USAGE_CRITICAL_PERCENT
    return :warning if pct.to_f >= BUDGET_USAGE_WARNING_PERCENT

    :safe
  end

  def budget_usage_percent(pct)
    return "—" if pct.nil?

    number_to_percentage(pct, precision: 0)
  end

  def budget_usage_width(pct)
    [ [ pct.to_f, 0 ].max, 100 ].min.round
  end

  def budget_usage_message(level)
    t("reports.budgets.usage_messages.#{level}")
  end

  # Chartkick series for the budget-vs-actual chart. The budget is one series;
  # actual spending is split by consumption level so each bar keeps its own
  # semantic color without any client-side calculation.
  def budget_chart_data(rows)
    series = [ { name: t("reports.budgets.budget"), data: rows.map { |row| [ row[:category_name], row[:budget].to_f ] } } ]
    colors = [ "#7FA7D8" ]

    {
      safe: [ "#0e9f6e", t("reports.budgets.chart.safe") ],
      warning: [ "#e9a23b", t("reports.budgets.chart.warning") ],
      critical: [ "#e0254b", t("reports.budgets.chart.critical") ]
    }.each do |level, (color, label)|
      data = rows.select { |row| budget_usage_level(row[:pct_used]) == level }
                 .map { |row| [ row[:category_name], row[:actual].to_f ] }
      next if data.empty?

      series << { name: label, data: data }
      colors << color
    end

    { series: series, colors: colors }
  end

  def budget_chart_height(rows)
    "#{[ rows.size * 46 + 90, 280 ].max}px"
  end

  def delta_badge(delta_pct, good_when_positive: false)
    return content_tag(:span, "—", class: "text-muted") if delta_pct.blank?

    up = delta_pct >= 0
    color = up == good_when_positive ? "text-success" : "text-danger"
    icon = up ? "ti-arrow-up-right" : "ti-arrow-down-right"
    content_tag(:span, class: "#{color} small") do
      content_tag(:i, "", class: "ti #{icon} me-1") + "#{number_with_delimiter(delta_pct.abs, precision: 1)}% " +
        t("reports.period.vs_previous")
    end
  end

  # Table variant of the change label: green/red arrow with the percentage,
  # em dash when there is no comparable previous data.
  def category_delta_label(delta_pct)
    return content_tag(:span, "—", class: "text-muted") if delta_pct.blank?

    up = delta_pct >= 0
    color = up ? "text-success" : "text-danger"
    icon = up ? "ti-arrow-up-right" : "ti-arrow-down-right"
    content_tag(:span, class: "#{color} small text-nowrap") do
      content_tag(:i, "", class: "ti #{icon} me-1") +
        "#{number_with_delimiter(delta_pct.abs, precision: 1)}% #{t('reports.period.vs_previous')}"
    end
  end

  def usage_progress(pct_used)
    pct = [ [ pct_used.to_f, 0 ].max, 100 ].min
    variant = pct_used.to_f > 100 ? "danger" : (pct_used.to_f >= Budget::NEAR_LIMIT_PERCENT ? "warning" : "success")
    content_tag(:div, class: "progress et-progress-8") do
      content_tag(:div, "", class: "progress-bar bg-#{variant} et-w-#{pct.round}",
                        role: "progressbar", "aria-valuenow": pct_used, "aria-valuemin": 0, "aria-valuemax": 100)
    end
  end

  # Compact secondary note for the overview KPI cards. Income has no income
  # denominator, so it shows the comparison delta or its registered count.
  def overview_income_note(overview)
    return delta_badge(overview[:income][:delta_pct], good_when_positive: true) if overview[:income][:delta_pct]

    return t("reports.overview.income_no_history") if overview[:income][:count].zero?

    t("reports.overview.income_note", count: overview[:income][:count])
  end

  def overview_expense_note(overview, analysis)
    return t("reports.overview.expense_empty") if overview[:expenses][:total].zero?

    share = analysis[:expense_share_pct]
    return t("reports.overview.expense_no_income") unless share

    content_tag(:span, t("reports.overview.expense_share_note",
                         pct: number_to_percentage(share, precision: 1)),
                data: { testid: "expense-share-note" })
  end

  def overview_debt_note(overview)
    return t("reports.overview.debt_empty") if overview[:debt][:count].zero?

    t("reports.overview.debt_note", count: overview[:debt][:count])
  end

  def overview_net_note(analysis)
    rate = analysis[:savings_rate]
    return t("reports.overview.net_note") unless rate

    t("reports.overview.net_share_note", pct: number_to_percentage(rate, precision: 1))
  end

  # The progress track uses the project's generated width classes, keeping
  # dynamic percentages out of inline styles.
  def report_progress_class(pct)
    width = [ [ pct.to_f.round, 0 ].max, 100 ].min
    "et-w-#{width}"
  end

  def analysis_alert_icon(kind)
    case kind.to_s
    when "decrease" then "trending-down"
    when "increase" then "trending-up"
    else "alert-triangle"
    end
  end

  def analysis_alert_tone(kind)
    kind.to_s == "decrease" ? "positive" : "attention"
  end

  def period_presets(user: nil)
    user ||= current_user if respond_to?(:current_user)
    presets = Reports::Period.cycles_enabled?(user) ? Reports::Period::CYCLE_PRESETS : Reports::Period::PRESETS

    presets.map do |preset|
      [ period_preset_label(preset, user), preset ]
    end
  end

  # Preset selected in the period control. With a configured financial cycle
  # the default is the current cycle, matching how the reports resolve an
  # omitted period.
  def selected_period_preset(user: nil)
    return params[:period] if params[:period].present?

    user ||= current_user if respond_to?(:current_user)
    Reports::Period.cycles_enabled?(user) ? "this_cycle" : "this_month"
  end

  # The two single-cycle presets name their concrete range ("Este ciclo
  # (Oct 20 – Nov 4)") so the selector is unambiguous about which months it
  # covers; multi-cycle and calendar presets keep their static labels.
  def period_preset_label(preset, user)
    base = t("reports.period.presets.#{preset}")
    return base unless user.present? && %w[this_cycle last_cycle].include?(preset)

    cycle = preset == "this_cycle" ? PayCycle.current(user) : PayCycle.previous(user)
    "#{base} (#{cycle.label})"
  end

  def money_source_options
    @money_source_options ||= if current_user.present?
      current_user.money_sources.active.payment_sources.order(:kind, :name).pluck(:name, :id)
    else
      []
    end
  end

  # "Origen del gasto" report: presentation for the source-type groups. The
  # keys come from Reports::MoneySources, so colors/icons stay consistent
  # between the donut, legend, bars and table.
  MONEY_SOURCE_GROUP_COLORS = {
    "accounts" => "#2a6df5",
    "credit_cards" => "#7929e8",
    "cash" => "#0e9f6e",
    "loans" => "#b26a00",
    "pockets" => "#6d7d8c",
    "other" => "#9ca3af"
  }.freeze

  MONEY_SOURCE_GROUP_ICONS = {
    "accounts" => "building-bank",
    "credit_cards" => "credit-card",
    "cash" => "cash",
    "loans" => "coin",
    "pockets" => "pig-money",
    "other" => "wallet"
  }.freeze

  MONEY_SOURCE_GROUP_TONES = {
    "accounts" => "blue",
    "credit_cards" => "purple",
    "cash" => "green",
    "loans" => "amber",
    "pockets" => "gray",
    "other" => "gray"
  }.freeze

  def money_source_group_label(key)
    t("reports.money_sources.groups.#{key}", default: key.to_s.humanize)
  end

  def money_source_group_icon(key)
    MONEY_SOURCE_GROUP_ICONS.fetch(key.to_s, "wallet")
  end

  def money_source_group_tone(key)
    MONEY_SOURCE_GROUP_TONES.fetch(key.to_s, "gray")
  end

  def money_source_group_color(key)
    MONEY_SOURCE_GROUP_COLORS.fetch(key.to_s, MONEY_SOURCE_GROUP_COLORS["other"])
  end

  def money_source_filter_options
    [
      [ t("reports.money_sources.filters.all_sources"), "" ],
      [ t("reports.money_sources.filters.accounts"), "accounts" ],
      [ t("reports.money_sources.filters.credit_cards"), "credit_cards" ],
      [ t("reports.money_sources.filters.cash"), "cash" ]
    ]
  end

  # Percentages come from the service already rounded; nil means the base was
  # zero, so the UI shows an em dash rather than a misleading 0%.
  def money_source_share_label(pct)
    return "—" if pct.nil?

    number_to_percentage(pct, precision: 1)
  end

  def money_source_donut_data(groups)
    groups.map { |group| [ money_source_group_label(group[:key]), group[:total].to_f ] }
  end

  def money_source_donut_colors(groups)
    groups.map { |group| money_source_group_color(group[:key]) }
  end

  def money_source_donut_library
    { cutout: "72%", plugins: { legend: { display: false } } }
  end

  def money_source_detail_path(source_id)
    reports_transactions_path(
      filter_params_for(money_source_id: source_id, credit_card_id: nil, loan_id: nil,
                        category_id: nil, uncategorized: nil)
    )
  end

  def credit_card_options
    @credit_card_options ||= current_user.present? ? current_user.money_sources.active.by_kind("credit_card").map { |s| [ s.name, s.id ] } : []
  end

  def loan_options
    @loan_options ||= current_user.present? ? current_user.money_sources.active.by_kind("loan").map { |s| [ s.name, s.id ] } : []
  end

  # Chart.js renders to canvas and cannot resolve CSS var() colors, so the
  # chart palette is hardcoded as hex values here.
  CHART_COLORS = %w[
    #7FA7D8 #9B8BC4 #D48FA8 #D99A72 #D8B45C #75B89B #70B8C5
    #8299C7 #8EAF8B #B08FC2 #C8877D #7FAFA8 #B59A7A #8D9BB8 #C19A6B
  ].freeze

  # Spending-trend presentation: grouping choices, chart palette and the
  # drill-down URLs that keep the shared report filters.
  TREND_GRANULARITIES = %w[day week month].freeze
  TREND_EXPENSE_COLOR = "#7FA7D8"
  TREND_PEAK_COLOR = "#F27662"

  def trend_granularity_options
    TREND_GRANULARITIES.map do |key|
      { key: key, label: t("reports.trend.granularity.#{key}") }
    end
  end

  def current_trend_granularity
    params[:granularity].presence_in(TREND_GRANULARITIES) ||
      @spending_trend&.dig(:granularity) || "day"
  end

  def trend_granularity_active?(key)
    current_trend_granularity == key
  end

  def trend_chart_colors(series)
    peak_index = trend_peak_bucket_index(series)

    series.each_with_index.map do |point, index|
      point[:total].to_d.positive? && index == peak_index ? TREND_PEAK_COLOR : TREND_EXPENSE_COLOR
    end
  end

  def trend_peak_bucket_index(series)
    positive = series.each_with_index.select { |point, _index| point[:total].to_d.positive? }
    positive.max_by { |point, _index| point[:total] }&.last
  end

  def trend_chart_library(trend)
    {
      animation: false,
      scales: {
        x: {
          grid: { display: false },
          ticks: {
            autoSkip: true,
            autoSkipPadding: 12,
            maxTicksLimit: trend[:bucket] == :day ? 12 : 8,
            maxRotation: 0,
            minRotation: 0
          }
        },
        y: {
          beginAtZero: true,
          grid: { color: "rgba(148, 163, 184, 0.18)" },
          ticks: { maxTicksLimit: 5 }
        }
      }
    }
  end

  def trend_chart_tooltips(series)
    series.map do |point|
      count = point[:count].to_i
      {
        total: "#{t('reports.trend.tooltip_total')}: #{money_amount(point[:total])}",
        count: count.positive? ? t("reports.trend.tooltip_transactions", count: count) : nil
      }.compact
    end
  end

  def trend_drill_down_url(point)
    return nil unless point && point[:total].to_d.positive?

    reports_transactions_path(
      filter_params_for(period: "custom", start_date: point[:range_start], end_date: point[:range_end])
    )
  end

  def trend_peak_drill_down_url(trend)
    trend_drill_down_url(trend[:peak])
  end

  def trend_peak_date_label(peak)
    return t("reports.trend.peak_empty") unless peak

    I18n.l(peak[:date], format: "%-d de %B").downcase
  end

  def trend_legend_peak_label(trend)
    t(trend[:bucket] == :day ? "reports.trend.legend_peak_day" : "reports.trend.legend_peak_period")
  end

  def trend_filters_active?
    %i[category_id money_source_id uncategorized].any? { |key| params[key].present? }
  end

  def trend_insight_icon(key)
    case key.to_s
    when "concentration" then "chart-pie"
    when "patterns" then "calendar-stats"
    else "alert-triangle"
    end
  end

  def report_clear_params
    filter_params_for.slice(:period, :start_date, :end_date, :granularity)
  end

  def filter_params_for(**overrides)
    base = params.to_unsafe_h.slice("period", "start_date", "end_date", "category_id",
                                    "money_source_id", "credit_card_id", "loan_id",
                                    "uncategorized", "granularity")
    (base.symbolize_keys.merge(overrides)).compact_blank
  end

  # Category rows always keep the selected period and source filters; a nil
  # category is the real "Sin categoría" bucket, so it uses the dedicated
  # uncategorized filter instead of dropping the category condition.
  def category_spending_detail_path(category)
    overrides = if category[:id].present?
      { category_id: category[:id], uncategorized: nil }
    else
      { category_id: nil, uncategorized: 1 }
    end
    reports_transactions_path(filter_params_for(**overrides))
  end

  def report_category_swatch_class(index)
    "et-swatch-r#{index % 15}"
  end

  def next_due_date_label(day)
    candidate = Date.new(Date.current.year, Date.current.month, day.to_i)
    candidate = candidate.next_month if candidate < Date.current
    candidate
  rescue Date::Error, ArgumentError, TypeError
    Date.current.end_of_month
  end

  # Available-cycle report: prefer the category's own icon (from the
  # `categories.icon` field) so the table stays consistent with the rest of
  # the app; fall back to a name-based heuristic for legacy categories
  # without a stored icon.
  def available_cycle_category_icon(category_name, icon = nil)
    stored = icon.to_s.strip
    return stored if stored.match?(/\Ati-[a-z0-9-]+\z/)

    name = category_name.to_s.downcase
    case name
    when /vivienda|arriendo|administraci/
      "ti-home"
    when /servicio|internet|energ|agua|celular|luz/
      "ti-bolt"
    when /transporte|carro|soat|gasolina|moto/
      "ti-car"
    when /salud|gimnasio|médic|medic|seguro/
      "ti-heartbeat"
    when /educaci|colegio|universidad|estudio/
      "ti-school"
    when /comida|mercado|restaurante|supermercado/
      "ti-shopping-cart"
    else
      "ti-receipt"
    end
  end

  def available_cycle_category_tone(category_name)
    name = category_name.to_s
    return "purple" if name.blank?

    AVAILABLE_CYCLE_TONES[name.bytes.sum % AVAILABLE_CYCLE_TONES.size]
  end

  def available_cycle_due_label(expense)
    return t("reports.available_cycle.no_date", default: "Sin fecha") if expense[:due_date].blank?
    return t("reports.available_cycle.overdue", default: "Vencido") if expense[:overdue]
    return t("reports.available_cycle.due_today", default: "Hoy") if expense[:due_today]

    days = expense[:days_until_due].to_i
    "En #{days} #{days == 1 ? 'día' : 'días'}"
  end

  def available_cycle_due_class(expense)
    return "is-none" if expense[:due_date].blank?
    return "is-late" if expense[:overdue]
    return "is-today" if expense[:due_today]
    return "is-soon" if expense[:due_soon]

    "is-upcoming"
  end

  def available_cycle_share(value, total)
    total = total.to_d
    value = value.to_d
    return (value.positive? ? 100 : 0) if total.zero?

    [ [ (value / total * 100).round, 0 ].max, 100 ].min
  end

  def available_cycle_percentage(value, total)
    total = total.to_d
    return "0%" if total.zero? && value.to_d.zero?
    return "—" if total.zero?

    "#{(value.to_d / total * 100).round}%"
  end
end
