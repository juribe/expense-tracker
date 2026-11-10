# frozen_string_literal: true

# Reports::PerspectivesHelper
# Presentation helpers for the perspectives report: importance labels,
# finding icons, variation formatting and the drill-down URLs that keep the
# current period and filters.
module Reports::PerspectivesHelper
  FINDING_ICONS = {
    spending_increase: "trending-up",
    spending_decrease: "trending-down",
    spending_decrease_records: "alert-triangle",
    category_growth: "chart-bar",
    category_reduction: "chart-bar",
    unusual_expense: "receipt",
    concentration: "chart-pie",
    income_positive: "wallet",
    income_negative: "alert-triangle",
    no_income: "wallet-off",
    recurring: "repeat"
  }.freeze

  def perspective_importance_label(importance)
    I18n.t("reports.perspectives.importance.#{importance}")
  end

  def perspective_finding_icon(type)
    FINDING_ICONS.fetch(type.to_sym, "sparkles")
  end

  def perspective_metric_class(tone)
    case tone.to_s
    when "negative" then "is-negative"
    when "positive" then "is-positive"
    else "is-neutral"
    end
  end

  def perspective_variation_value(comparison)
    pct = comparison[:delta_pct]
    return "—" unless comparison[:available] && pct

    arrow = pct.positive? ? "↑" : (pct.negative? ? "↓" : "→")
    "#{arrow} #{percentage_compact(pct.abs)}"
  end

  def perspective_variation_note(comparison)
    return I18n.t("reports.perspectives.variation_no_base") unless comparison[:available] && comparison[:delta_pct]

    I18n.t("reports.perspectives.variation_note",
           amount: MoneyFormat.currency(comparison[:delta].abs),
           period: perspective_comparison_period(comparison))
  end

  def perspective_comparison_period(comparison)
    comparison[:partial] ? I18n.t("reports.perspectives.period_labels.previous_partial") :
                           I18n.t("reports.perspectives.period_labels.previous")
  end

  def perspective_evolution_delta_label(comparison)
    return I18n.t("reports.perspectives.variation_no_base") unless comparison[:available] && comparison[:delta_pct]

    "#{perspective_variation_value(comparison)} vs. #{perspective_comparison_period(comparison)}"
  end

  def perspective_action_url(action)
    base = filter_params_for

    case action[:key].to_s
    when "category"
      reports_by_category_path(base.except(:uncategorized).merge(category_id: action[:category_id]).compact_blank)
    when "transaction"
      reports_transactions_path(
        base.merge(period: "custom", start_date: action[:date], end_date: action[:date],
                   category_id: action[:category_id], modal: 1).compact_blank
      )
    when "overview"
      reports_overview_path(base)
    when "recurring"
      reports_recurring_path(base)
    when "expenses"
      expenses_path(q: action[:query], start_date: action[:start_date], end_date: action[:end_date])
    when "trends"
      reports_trends_path(base)
    when "budgets"
      reports_budgets_path(base.except(:money_source_id, :uncategorized)
                               .merge(category_id: action[:category_id]).compact_blank)
    when "goals"
      goals_path
    when "money_sources"
      reports_money_sources_path(base)
    when "transactions"
      reports_transactions_path(base)
    else
      reports_insights_path(base)
    end
  end

  def perspective_action_data(action, url)
    action[:modal] ? { transactions_modal_url: url } : {}
  end

  def percentage_compact(value)
    number_to_percentage(value, precision: 1, strip_insignificant_zeros: true)
  end
end
