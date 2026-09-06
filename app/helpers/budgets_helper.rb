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
    when :over_budget then "bi-x-circle"
    when :near_limit then "bi-exclamation-triangle"
    else "bi-check-circle"
    end
  end

  def budget_status_label(status)
    t("budgets.status.#{status}")
  end

  def budget_summary_counts(budgets, month)
    {
      total: budgets.size,
      near_limit: budgets.count { |budget| budget.status_for(month) == :near_limit },
      over_budget: budgets.count { |budget| budget.status_for(month) == :over_budget }
    }
  end

  def budget_progress_data(budget, month)
    {
      spent: budget.spent_for(month),
      percentage: budget.percentage_for(month),
      status: budget.status_for(month)
    }
  end
end
