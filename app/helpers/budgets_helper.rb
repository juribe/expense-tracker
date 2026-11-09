# BudgetsHelper
# Presentation helpers for the budgets index: period navigation, summary
# metrics, four-level usage states and sorting.
#
# Methods: budget_summary_counts, budget_period_summary, budget_progress_data,
#          budget_display_state, budget_display_label, budget_display_icon,
#          budget_sort_options, budget_sort_value, budget_sorted,
#          budget_period_range_label, budget_analysis_path
#
# Example: budget_display_state(92.4) # => :near_limit
module BudgetsHelper
  BUDGET_ATTENTION_PERCENT = 75
  BUDGET_NEAR_LIMIT_PERCENT = 90
  BUDGET_SORT_KEYS = %w[usage available budget spent].freeze

  def budget_summary_counts(budgets, period)
    {
      total: budgets.size,
      near_limit: budgets.count { |budget| budget.status_for(period) == :near_limit },
      over_budget: budgets.count { |budget| budget.status_for(period) == :over_budget }
    }
  end

  def budget_progress_data(budget, period)
    {
      spent: budget.spent_for(period),
      percentage: budget.percentage_for(period)
    }
  end

  # Aggregate metrics for the selected period. The per-budget financial values
  # still come from Budget so the index never reimplements its calculations.
  def budget_period_summary(budgets, period)
    rows = budgets.map do |budget|
      amount = budget.amount_for(period)
      spent = budget.spent_for(period)
      { amount: amount, spent: spent, percentage: budget.percentage_for(period) }
    end

    total_budget = rows.sum { |row| row[:amount] }
    total_spent = rows.sum { |row| row[:spent] }
    states = rows.map { |row| budget_display_state(row[:percentage]) }

    {
      total_budget: total_budget,
      total_spent: total_spent,
      total_available: total_budget - total_spent,
      usage_percentage: total_budget.positive? ? (total_spent / total_budget * 100) : 0,
      count: rows.size,
      risk_count: rows.count { |row| row[:percentage].to_f >= BUDGET_NEAR_LIMIT_PERCENT },
      attention_count: states.count(:attention),
      near_limit_count: states.count(:near_limit),
      over_budget_count: states.count(:over_budget)
    }
  end

  # Presentation thresholds for the four-level usage scale. The domain status
  # on Budget keeps its own thresholds for alerts and other modules.
  def budget_display_state(percentage)
    pct = percentage.to_f
    return :over_budget if pct >= 100
    return :near_limit if pct >= BUDGET_NEAR_LIMIT_PERCENT
    return :attention if pct >= BUDGET_ATTENTION_PERCENT

    :on_track
  end

  def budget_display_label(state)
    t("budgets.display_status.#{state}")
  end

  def budget_display_icon(state)
    {
      on_track: "ti-circle-check",
      attention: "ti-clock",
      near_limit: "ti-alert-triangle",
      over_budget: "ti-alert-circle"
    }.fetch(state)
  end

  def budget_sort_options
    [
      [ t("budgets.sort.default"), "default" ],
      [ t("budgets.sort.usage"), "usage" ],
      [ t("budgets.sort.available"), "available" ],
      [ t("budgets.sort.budget"), "budget" ],
      [ t("budgets.sort.spent"), "spent" ]
    ]
  end

  def budget_sort_value(value)
    BUDGET_SORT_KEYS.include?(value.to_s) ? value.to_s : "default"
  end

  def budget_sorted(budgets, sort, period)
    return budgets unless BUDGET_SORT_KEYS.include?(sort)

    rows = budgets.to_a
    case sort
    when "usage"
      rows.sort_by { |budget| [ -budget.percentage_for(period).to_f, budget.category.name.downcase ] }
    when "available"
      rows.sort_by { |budget| [ budget.remaining_for(period), budget.category.name.downcase ] }
    when "budget"
      rows.sort_by { |budget| [ -budget.amount_for(period).to_f, budget.category.name.downcase ] }
    when "spent"
      rows.sort_by { |budget| [ -budget.spent_for(period).to_f, budget.category.name.downcase ] }
    end
  end

  def budget_period_label(period)
    period.is_a?(PayCycle::Cycle) ? period.label : l(period, format: :month_year)
  end

  def budget_period_range_label(period)
    return period.range_label if period.is_a?(PayCycle::Cycle)

    range = period.beginning_of_month..period.end_of_month
    "#{l(range.begin, format: "%b %e").squeeze(" ").strip} – #{l(range.end, format: "%b %e").squeeze(" ").strip}"
  end

  # Reuses the budget analysis report scoped to this category and period.
  def budget_analysis_path(budget, period)
    range = period.is_a?(PayCycle::Cycle) ? period.to_range : period.beginning_of_month..period.end_of_month

    reports_budgets_path(
      category_id: budget.category_id,
      period: "custom",
      start_date: range.begin.iso8601,
      end_date: range.end.iso8601
    )
  end
end
