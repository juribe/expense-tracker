# frozen_string_literal: true

# Reports::Budgets
# Budget vs actual spending per category, reusing the Budget model and its
# near-limit threshold. Budgets are monthly, so multi-month periods scale the
# monthly amount by the covered months.
#
# Associations: none (aggregates over Budget + actual expenses)
# Methods: call
#
# Example: Reports::Budgets.new(user: user, filter: filter).call[:rows]
class Reports::Budgets < Reports::Base
  def call
    budgets = Budget.active.for_user(user).includes(:category)
    spending = category_totals(period.range)
    rows = budgets.map { |budget| budget_row(budget, spending) }

    {
      period: period,
      rows: rows.sort_by { |row| -(row[:actual] <=> 0) },
      total_budget: rows.sum { |row| row[:budget] },
      total_actual: rows.sum { |row| row[:actual] },
      total_remaining: rows.sum { |row| row[:remaining] },
      unbudgeted: unbudgeted_section(spending, budgets)
    }
  end

  private

  def category_totals(range)
    filter.expense_scope(range).where.missing(:payments)
          .group(:category_id)
          .sum(Arel.sql("ABS(transactions.amount)"))
          .transform_values(&:to_d)
  end

  def budget_row(budget, spending)
    actual = spending[budget.category_id].to_d
    budget_amount = budget.monthly_amount.to_d * span_months
    remaining = budget_amount - actual
    pct_used = budget_amount.positive? ? (actual / budget_amount * 100).round(1) : 0.0

    {
      id: budget.id, category_id: budget.category_id, category_name: budget.category.name,
      budget: budget_amount, actual: actual, remaining: remaining,
      pct_used: pct_used, status: status(pct_used)
    }
  end

  def unbudgeted_section(spending, budgets)
    budgeted_ids = budgets.map(&:category_id)
    unbudgeted = spending.reject { |category_id, _| budgeted_ids.include?(category_id) }
    return nil if unbudgeted.empty?

    categories = Category.where(id: unbudgeted.keys).index_by(&:id)
    total = unbudgeted.values.sum
    {
      total: total,
      categories: unbudgeted.map do |category_id, actual|
        { id: category_id, name: categories[category_id]&.name, actual: actual }
      end
    }
  end

  def status(pct_used)
    if pct_used > 100.0
      :over_budget
    elsif pct_used >= Budget::NEAR_LIMIT_PERCENT
      :near_limit
    else
      :on_track
    end
  end

  def span_months
    end_month = period.range.end.year * 12 + period.range.end.month
    begin_month = period.range.begin.year * 12 + period.range.begin.month
    end_month - begin_month + 1
  end
end
