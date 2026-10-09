# BudgetsHelper
# Methods: budget_status_class, budget_status_icon, budget_status_label,
#          budget_summary_counts, budget_metrics
#
# Example: budget_summary_counts(budgets, month) # => { total:, near_limit:, over_budget: }
module BudgetsHelper
  def budget_status_class(status)
    case status.to_sym
    when :over_budget then "bg-danger"
    when :near_limit then "bg-warning text-dark"
    else "bg-success"
    end
  end

  def budget_status_icon(status)
    case status.to_sym
    when :over_budget then "ti-circle-x"
    when :near_limit then "ti-alert-triangle"
    else "ti-circle-check"
    end
  end

  def budget_status_label(status)
    t("budgets.status.#{status}")
  end

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
      percentage: budget.percentage_for(period),
      status: budget.status_for(period)
    }
  end

  # Calendar months navigate by month param, pay cycles by an anchor date
  # param that snaps into the adjacent cycle.
  def budget_prev_nav_path(period)
    period.is_a?(PayCycle::Cycle) ? budgets_path(cycle: period.starts - 1.day) : budgets_path(month: period.prev_month)
  end

  def budget_next_nav_path(period)
    period.is_a?(PayCycle::Cycle) ? budgets_path(cycle: period.ends + 1.day) : budgets_path(month: period.next_month)
  end

  def budget_period_label(period)
    period.is_a?(PayCycle::Cycle) ? period.label : l(period, format: :month_year)
  end

  def budget_current_period?(period)
    if period.is_a?(PayCycle::Cycle)
      period == PayCycle.current(current_user)
    else
      period.beginning_of_month == Time.zone.today.beginning_of_month
    end
  end
end
