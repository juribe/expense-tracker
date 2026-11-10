# frozen_string_literal: true

# Reports::Perspectives::Metrics
# Single pass of the numbers the perspectives report needs: income, real
# expenses, balance, per-category and per-source distribution. "Real expenses"
# uses the same accounting split as every other report (debt payments are not
# consumption spending), and transfers are a separate model, so they never
# enter these totals.
#
# When the selected period is still in progress, the comparison range is the
# same number of elapsed days of the previous equivalent period. This keeps a
# partial cycle from being compared against a complete one without warning.
#
# Methods: call
#
# Example: Reports::Perspectives::Metrics.new(user: user, filter: filter).call[:balance]
class Reports::Perspectives::Metrics
  def initialize(user:, filter:)
    @user = user
    @filter = filter
    @period = filter.period
  end

  attr_reader :user, :filter, :period

  def call
    expenses = expense_metrics

    {
      period: period,
      current_range: current_range,
      previous_range: period.previous_range,
      comparison_range: comparison_range,
      partial: partial?,
      elapsed_days: elapsed_days,
      income: income_metrics,
      expenses: expenses,
      balance: income_metrics[:total] - expenses[:total],
      categories: category_rows,
      sources: source_rows,
      largest_expense: largest_expense
    }
  end

  private

  def income_metrics
    @income_metrics ||= begin
      current = filter.income_scope_without_category(current_range)
      previous = filter.income_scope_without_category(comparison_range)
      total = current.sum(:amount).to_d
      previous_total = previous.sum(:amount).to_d

      {
        total: total,
        previous: previous_total,
        count: current.count,
        previous_count: previous.count,
        delta: total - previous_total,
        delta_pct: percentage_delta(total, previous_total)
      }
    end
  end

  def expense_metrics
    @expense_metrics ||= begin
      current_total, current_count = aggregate_expenses(current_range)
      previous_total, previous_count = aggregate_expenses(comparison_range)

      {
        total: current_total,
        previous: previous_total,
        count: current_count,
        previous_count: previous_count,
        average: current_count.positive? ? current_total / current_count : nil,
        delta: current_total - previous_total,
        delta_pct: percentage_delta(current_total, previous_total)
      }
    end
  end

  def aggregate_expenses(range)
    total, count = filter.actual_expense_scope(range)
                         .pick(Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
    [ total.to_d, count.to_i ]
  end

  def category_rows
    current = grouped_categories(current_range)
    previous = grouped_categories(comparison_range)
    grand_total = current.values.sum { |row| row[:total].to_d }
    category_ids = (current.keys + previous.keys).uniq

    category_ids.map do |category_id|
      current_row = current[category_id] || {}
      previous_row = previous[category_id] || {}
      total = current_row[:total].to_d
      previous_total = previous_row[:total].to_d

      {
        id: category_id,
        name: current_row[:name] || previous_row[:name] || uncategorized,
        icon: current_row[:icon] || previous_row[:icon],
        total: total,
        previous: previous_total,
        count: current_row[:count].to_i,
        previous_count: previous_row[:count].to_i,
        delta: total - previous_total,
        delta_pct: percentage_delta(total, previous_total),
        share_pct: grand_total.positive? ? (total / grand_total * 100).round(1) : nil
      }
    end.sort_by { |row| -row[:total] }
  end

  def grouped_categories(range)
    filter.actual_expense_scope(range)
          .left_joins(:category)
          .group("transactions.category_id", "categories.name", "categories.icon")
          .pluck(
            Arel.sql("transactions.category_id"),
            Arel.sql("categories.name"),
            Arel.sql("categories.icon"),
            Arel.sql("ABS(SUM(transactions.amount))"),
            Arel.sql("COUNT(*)")
          )
          .to_h do |category_id, name, icon, total, count|
      [ category_id, { name: name, icon: icon, total: total.to_d, count: count.to_i } ]
    end
  end

  def source_rows
    grand_total = expenses_total
    rows = filter.actual_expense_scope(current_range)
                 .left_joins(:money_source)
                 .group("transactions.money_source_id", "money_sources.name", "money_sources.kind")
                 .pluck(
                   Arel.sql("transactions.money_source_id"),
                   Arel.sql("money_sources.name"),
                   Arel.sql("money_sources.kind"),
                   Arel.sql("ABS(SUM(transactions.amount))"),
                   Arel.sql("COUNT(*)")
                 )

    rows.map do |source_id, name, kind, total, count|
      {
        id: source_id,
        name: name || I18n.t("reports.perspectives.unknown_source", default: "Sin fuente"),
        kind: kind,
        total: total.to_d,
        count: count.to_i,
        share_pct: grand_total.positive? ? (total.to_d / grand_total * 100).round(1) : nil
      }
    end.sort_by { |row| -row[:total] }
  end

  def largest_expense
    filter.actual_expense_scope(current_range)
          .where.not(category_id: nil)
          .order(Arel.sql("ABS(transactions.amount) DESC"))
          .first
  end

  def expenses_total
    expense_metrics[:total]
  end

  def partial?
    @partial ||= period.range.end >= Date.current
  end

  def current_range
    @current_range ||= partial? ? period.range.begin..elapsed_end : period.range
  end

  def comparison_range
    @comparison_range ||= if partial?
      previous = period.previous_range
      previous.begin..[ previous.begin + elapsed_days - 1, previous.end ].min
    else
      period.previous_range
    end
  end

  def elapsed_end
    [ [ period.range.end, Date.current ].min, period.range.begin ].max
  end

  def elapsed_days
    (elapsed_end - period.range.begin).to_i + 1
  end

  def percentage_delta(current, previous)
    previous = previous.to_d
    return nil if previous.zero?

    ((current.to_d - previous) / previous * 100).round(1)
  end

  def uncategorized
    I18n.t("reports.uncategorized", default: "Sin categoría")
  end
end
