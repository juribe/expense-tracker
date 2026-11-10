# frozen_string_literal: true

# Reports::Perspectives::Findings
# Deterministic detection rules for the perspectives report. Every finding is
# backed by calculated metrics: no rule invents an amount, a percentage or a
# recurrence. Findings are deduplicated and capped, and the whole section stays
# empty when there is no previous period to compare against.
#
# Methods: call
#
# Example: Reports::Perspectives::Findings.new(user:, filter:, metrics:, comparison:).call
class Reports::Perspectives::Findings
  def initialize(user:, filter:, metrics:, comparison:)
    @user = user
    @filter = filter
    @metrics = metrics
    @comparison = comparison
  end

  attr_reader :user, :filter, :metrics, :comparison

  def call
    return [] unless comparison[:available]

    deduplicate(
      spending_change +
      income_vs_expenses +
      unusual_expense +
      concentration +
      recurring_payments +
      category_changes
    ).sort_by { |finding| -finding[:score] }
     .first(Reports::Perspectives::Thresholds::MAX_FINDINGS)
  end

  private

  def spending_change
    pct = comparison[:delta_pct]
    return [] if pct.nil? || pct.abs < Reports::Perspectives::Thresholds::SPENDING_CHANGE_PCT

    if pct.positive?
      [ spending_increase(pct) ]
    elsif fewer_records?
      [ spending_decrease_records(pct) ]
    else
      [ spending_decrease(pct) ]
    end
  end

  def spending_increase(pct)
    finding(
      :spending_increase,
      importance: "attention",
      metric_tone: "negative",
      metric: "+#{percentage(pct)}",
      explanation: I18n.t("reports.perspectives.findings.spending_increase.explanation",
                          pct: percentage(pct), amount: currency(comparison[:delta].abs),
                          period: comparison_period),
      period_label: comparison_period_label,
      action: { key: :trends, label: I18n.t("reports.perspectives.actions.compare") },
      score: 100
    )
  end

  def spending_decrease(pct)
    finding(
      :spending_decrease,
      importance: "positive",
      metric_tone: "positive",
      metric: "-#{percentage(pct.abs)}",
      explanation: I18n.t("reports.perspectives.findings.spending_decrease.explanation",
                          pct: percentage(pct.abs), amount: currency(comparison[:delta].abs),
                          period: comparison_period),
      period_label: comparison_period_label,
      action: { key: :trends, label: I18n.t("reports.perspectives.actions.compare") },
      score: 100
    )
  end

  def spending_decrease_records(pct)
    finding(
      :spending_decrease_records,
      importance: "attention",
      metric_tone: "neutral",
      metric: "-#{percentage(pct.abs)}",
      explanation: I18n.t("reports.perspectives.findings.spending_decrease_records.explanation",
                          pct: percentage(pct.abs), current_count: comparison[:current_count],
                          previous_count: comparison[:previous_count]),
      period_label: comparison_period_label,
      action: { key: :transactions, label: I18n.t("reports.perspectives.actions.movements") },
      score: 100
    )
  end

  def fewer_records?
    previous_count = comparison[:previous_count].to_i
    return false unless previous_count.positive?

    comparison[:current_count].to_i < previous_count * Reports::Perspectives::Thresholds::LOW_RECORDING_RATIO
  end

  def income_vs_expenses
    income = metrics[:income][:total].to_d
    expenses = metrics[:expenses][:total].to_d

    if income.zero? && expenses.positive?
      [ no_income_finding(expenses) ]
    elsif income.positive? && expenses > income
      [ expense_over_income_finding(income, expenses) ]
    elsif income.positive? && income > expenses
      [ income_over_expense_finding(income, expenses) ]
    else
      []
    end
  end

  def no_income_finding(expenses)
    finding(
      :no_income,
      importance: "attention",
      metric_tone: "negative",
      metric: currency(expenses),
      explanation: I18n.t("reports.perspectives.findings.no_income.explanation", amount: currency(expenses)),
      period_label: I18n.t("reports.perspectives.period_labels.current_cycle"),
      action: { key: :transactions, label: I18n.t("reports.perspectives.actions.movements") },
      score: 92
    )
  end

  def expense_over_income_finding(income, expenses)
    finding(
      :income_negative,
      importance: "attention",
      metric_tone: "negative",
      metric: "-#{currency(expenses - income)}",
      explanation: I18n.t("reports.perspectives.findings.income_negative.explanation",
                          amount: currency(expenses - income)),
      period_label: I18n.t("reports.perspectives.period_labels.income_vs_expenses"),
      action: { key: :overview, label: I18n.t("reports.perspectives.actions.summary") },
      score: 95
    )
  end

  def income_over_expense_finding(income, expenses)
    finding(
      :income_positive,
      importance: "positive",
      metric_tone: "positive",
      metric: "+#{currency(income - expenses)}",
      explanation: I18n.t("reports.perspectives.findings.income_positive.explanation",
                          amount: currency(income - expenses)),
      period_label: I18n.t("reports.perspectives.period_labels.income_vs_expenses"),
      action: { key: :overview, label: I18n.t("reports.perspectives.actions.summary") },
      score: 90
    )
  end

  def unusual_expense
    expense = metrics[:largest_expense]
    return [] unless expense

    history = category_history(expense.category_id)
    return [] if history[:count] < Reports::Perspectives::Thresholds::UNUSUAL_MIN_HISTORY

    average = history[:total] / history[:count]
    return [] unless average.positive?

    amount = expense.amount.to_d.abs
    return [] if amount < Reports::Perspectives::Thresholds::UNUSUAL_MIN_AMOUNT
    return [] if amount < average * Reports::Perspectives::Thresholds::UNUSUAL_RATIO

    [
      finding(
        :unusual_expense,
        importance: "attention",
        metric_tone: "negative",
        metric: currency(amount),
        explanation: I18n.t("reports.perspectives.findings.unusual_expense.explanation",
                            amount: currency(amount), name: category_name(expense.category_id),
                            average: currency(average)),
        period_label: I18n.t("reports.perspectives.period_labels.history"),
        action: {
          key: :transaction,
          label: I18n.t("reports.perspectives.actions.movement"),
          expense_id: expense.id,
          date: expense.date.iso8601,
          category_id: expense.category_id,
          modal: true
        },
        score: 88,
        category_id: expense.category_id,
        data: { expense_id: expense.id, amount: amount, historical_average: average }
      )
    ]
  end

  def concentration
    return [] if filter.active_category_id.present?

    top = metrics[:categories].select { |row| row[:total].to_d.positive? }.max_by { |row| row[:total].to_d }
    return [] unless top
    return [] if top[:share_pct].nil?
    return [] if top[:share_pct] < Reports::Perspectives::Thresholds::CONCENTRATION_PCT

    [
      finding(
        :concentration,
        importance: "opportunity",
        metric_tone: "neutral",
        metric: percentage(top[:share_pct]),
        explanation: I18n.t("reports.perspectives.findings.concentration.explanation",
                            name: top[:name], pct: percentage(top[:share_pct])),
        period_label: I18n.t("reports.perspectives.period_labels.current_cycle"),
        action: { key: :category, label: I18n.t("reports.perspectives.actions.category", name: top[:name]),
                  category_id: top[:id] },
        score: 80,
        category_id: top[:id],
        data: { share_pct: top[:share_pct], total: top[:total] }
      )
    ]
  end

  def recurring_payments
    detection = recurring_detection
    return [] if detection[:rows].empty?

    monthly_total = detection[:total_monthly].to_d
    return [] unless monthly_total.positive?

    expenses_total = metrics[:expenses][:total].to_d
    share = expenses_total.positive? ? (monthly_total / expenses_total * 100).round(1) : 0
    return [] if share < Reports::Perspectives::Thresholds::RECURRING_MIN_SHARE_PCT

    top_row = detection[:rows].first
    range = recurring_range

    [
      finding(
        :recurring,
        importance: "opportunity",
        metric_tone: "neutral",
        metric: I18n.t("reports.perspectives.findings.recurring.metric", amount: currency(monthly_total)),
        explanation: I18n.t("reports.perspectives.findings.recurring.explanation",
                            count: detection[:rows].size, amount: currency(monthly_total),
                            pct: percentage(share)),
        period_label: I18n.t("reports.perspectives.period_labels.history"),
        action: {
          key: :expenses,
          label: I18n.t("reports.perspectives.actions.recurring_movements", name: top_row[:name]),
          query: top_row[:name],
          start_date: range.begin.iso8601,
          end_date: range.end.iso8601
        },
        score: 70,
        data: { count: detection[:rows].size, monthly_total: monthly_total, share_pct: share,
                rows: detection[:rows] }
      )
    ]
  end

  def category_changes
    return [] if filter.active_category_id.present?

    comparison[:top_growth].first(2).map { |row| category_growth_finding(row) } +
      comparison[:top_reduction].first(1).map { |row| category_reduction_finding(row) }
  end

  def category_growth_finding(row)
    explanation = if row[:delta_pct].nil?
      I18n.t("reports.perspectives.findings.category_growth.explanation_no_base",
             name: row[:name], amount: currency(row[:delta].abs))
    else
      I18n.t("reports.perspectives.findings.category_growth.explanation",
             name: row[:name], amount: currency(row[:delta].abs), pct: percentage(row[:delta_pct]))
    end

    finding(
      :category_growth,
      importance: "attention",
      metric_tone: "negative",
      metric: "+#{currency(row[:delta].abs)}",
      explanation: explanation,
      period_label: comparison_period_label,
      action: { key: :category, label: I18n.t("reports.perspectives.actions.category", name: row[:name]),
                category_id: row[:id] },
      score: 65,
      category_id: row[:id],
      data: row
    )
  end

  def category_reduction_finding(row)
    explanation = if row[:delta_pct].nil?
      I18n.t("reports.perspectives.findings.category_reduction.explanation_no_base",
             name: row[:name], amount: currency(row[:delta].abs))
    else
      I18n.t("reports.perspectives.findings.category_reduction.explanation",
             name: row[:name], amount: currency(row[:delta].abs), pct: percentage(row[:delta_pct].abs))
    end

    finding(
      :category_reduction,
      importance: "positive",
      metric_tone: "positive",
      metric: row[:delta_pct] ? "-#{percentage(row[:delta_pct].abs)}" : "-#{currency(row[:delta].abs)}",
      explanation: explanation,
      period_label: comparison_period_label,
      action: { key: :category, label: I18n.t("reports.perspectives.actions.category", name: row[:name]),
                category_id: row[:id] },
      score: 60,
      category_id: row[:id],
      data: row
    )
  end

  def finding(type, importance:, metric:, metric_tone:, explanation:, period_label:, action:, score:,
              category_id: nil, data: {})
    {
      type: type,
      title: I18n.t("reports.perspectives.findings.#{type}.title"),
      importance: importance,
      metric: metric,
      metric_tone: metric_tone,
      explanation: explanation,
      period_label: period_label,
      action: action,
      score: score,
      category_id: category_id,
      data: data
    }
  end

  def category_history(category_id)
    total, count = filter.actual_expense_scope(history_range)
                         .where(category_id: category_id)
                         .pick(Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
    { total: total.to_d, count: count.to_i }
  end

  def history_range
    start = metrics[:current_range].begin - Reports::Perspectives::Thresholds::RECURRING_LOOKBACK_MONTHS.months
    start..(metrics[:current_range].begin - 1.day)
  end

  def recurring_detection
    range = recurring_range
    window = Struct.new(:recurring_range).new(range)
    scope = filter.expense_scope(range)

    SavingsOpportunities::RecurringDetection.new(user: user, window: window, scope: scope).call
  end

  def recurring_range
    history_range.begin..metrics[:current_range].end
  end

  def category_name(category_id)
    metrics[:categories].find { |row| row[:id] == category_id }&.dig(:name) ||
      I18n.t("reports.uncategorized", default: "Sin categoría")
  end

  def deduplicate(findings)
    findings.uniq { |finding| [ finding[:type], finding[:category_id] ] }
  end

  def comparison_period
    comparison[:partial] ? I18n.t("reports.perspectives.period_labels.previous_partial") :
                           I18n.t("reports.perspectives.period_labels.previous")
  end

  def comparison_period_label
    I18n.t("reports.perspectives.period_labels.comparison",
           period: comparison_period)
  end

  def percentage(value)
    ActionController::Base.helpers.number_to_percentage(
      value, precision: 1, strip_insignificant_zeros: true
    )
  end

  def currency(value)
    MoneyFormat.currency(value)
  end
end
