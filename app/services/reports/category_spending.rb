# frozen_string_literal: true

# Reports::CategorySpending
# Actual spending (debt payments excluded) grouped by category, with share of
# total, transaction counts and previous-equivalent-period comparisons. Each
# row carries a lazy drill-down scope with its underlying expenses.
#
# Methods: call
#
# Example: Reports::CategorySpending.new(user: user, filter: filter).call[:categories]
class Reports::CategorySpending < Reports::Base
  def call
    current = grouped(period.range)
    previous = grouped(period.previous_range)
    grand_total = current.sum { |_, row| row[:total] }

    {
      period: period,
      total: grand_total,
      categories: current.map { |category_id, row| category_row(category_id, row, previous[category_id], grand_total) }
    }
  end

  private

  def grouped(range)
    base = filter.expense_scope(range).where.missing(:payments)
    base.left_joins(:category)
        .group("categories.id", "categories.name")
        .pluck(Arel.sql("categories.id"), Arel.sql("categories.name"),
               Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
        .index_by { |_id, _name, _total, _count| _id }
        .transform_values do |_id, name, total, count|
      { name: name, total: total.to_d, count: count.to_i, base: base }
    end
  end

  def category_row(category_id, row, previous_row, grand_total)
    previous = previous_row[:total].to_d if previous_row
    {
      id: category_id, name: row[:name] || I18n.t("reports.uncategorized", default: "Sin categoría"),
      total: row[:total], count: row[:count],
      share_pct: share_pct(row[:total], grand_total),
      previous: previous, delta_pct: delta_pct(row[:total], previous),
      scope: -> { drill_down(category_id, row[:base]) }
    }
  end

  def drill_down(category_id, base)
    category_id.nil? ? base.where(category_id: nil) : base.where(category_id: category_id)
  end

  def share_pct(part, total)
    return nil if total.zero?

    (part / total * 100).round(1)
  end

  def delta_pct(current, previous)
    self.class.delta_pct(current, previous) if previous
  end
end
