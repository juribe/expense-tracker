# frozen_string_literal: true

# Reports::Insights
# Deterministic spending insights built from the other reports' data. Only
# emits an insight when the underlying data clearly supports it, capped to a
# small set to avoid noise. Thresholds live in Reports::Thresholds.
#
# Methods: call
#
# Example: Reports::Insights.new(user: user, filter: filter).call
#   # => [{ rule:, kind:, message:, category_id:, data: }]
class Reports::Insights < Reports::Base
  HISTORICAL_MONTHS = 6

  def call
    rules.flat_map { |rule| send(rule) }
         .compact
         .first(Reports::Thresholds::MAX_INSIGHTS)
  end

  private

  def rules
    %i[spending_change category_spike category_unusual_average large_transaction
       transaction_count_unusual credit_utilization_increase recurring_commitment_increase
       debt_payment_increase]
  end

  def spending_change
    current = actual_total(period.range)
    previous = actual_total(period.previous_range)
    pct = integer_pct(current, previous)
    return [] if pct.nil?

    rule = pct.positive? ? :spending_increase : :spending_decrease
    return [] if pct.abs < Reports::Thresholds::SPENDING_SPIKE_PCT

    [ {
      rule: rule, kind: pct.positive? ? "increase" : "decrease",
      message: I18n.t("reports.insights.spending_#{rule == :spending_increase ? 'increase' : 'decrease'}",
                      pct: pct.abs),
      data: { total: current, previous: previous, delta_pct: pct }
    } ]
  end

  def category_spike
    Reports::CategorySpending.new(user: user, filter: filter).call[:categories]
                             .select { |row| row[:previous].to_d.positive? && row[:delta_pct] }
                             .select { |row| row[:delta_pct].abs >= Reports::Thresholds::CATEGORY_SPIKE_PCT }
                             .map do |row|
      {
        rule: row[:delta_pct].positive? ? :category_previous_period_increase : :category_previous_period_decrease,
        kind: row[:delta_pct].positive? ? "increase" : "decrease",
        message: I18n.t("reports.insights.category_#{row[:delta_pct].positive? ? 'increase' : 'decrease'}",
                        name: row[:name], pct: row[:delta_pct].round),
        category_id: row[:id],
        data: { total: row[:total], previous: row[:previous], delta_pct: row[:delta_pct].round }
      }
    end
  end

  def category_unusual_average
    current = grouped_categories(period.range)
    history = grouped_categories(history_range)
    return [] if history.empty?

    current.map do |category_id, row|
      historical = history[category_id]
      next unless historical
      next unless historical[:months] >= Reports::Thresholds::CATEGORY_AVERAGE_MIN_MONTHS

      average = historical[:total] / historical[:months]
      next unless average.positive?

      ratio = (row[:total] / average).round(2)
      next unless ratio >= Reports::Thresholds::CATEGORY_AVERAGE_RATIO

      {
        rule: :category_unusual_average, kind: "anomaly",
        message: I18n.t("reports.insights.category_unusual_average", name: row[:name],
                        pct: ((ratio - 1) * 100).round),
        category_id: category_id,
        data: { total: row[:total], historical_average: average, ratio: ratio }
      }
    end.compact
  end

  def large_transaction
    base = filter.expense_scope(period.range).where.missing(:payments)
    rows = base.pluck(Arel.sql("transactions.id"), Arel.sql("ABS(transactions.amount)"),
                      Arel.sql("transactions.description"), Arel.sql("transactions.category_id"))
    return [] if rows.size < 2

    total = rows.sum { |_id, amount, _desc, _cat| amount }
    average = total / rows.size
    outlier = rows.max_by { |_id, amount, _desc, _cat| amount }
    id, amount, description, category_id = outlier
    return [] if amount < Reports::Thresholds::LARGE_TRANSACTION_MIN
    return [] unless amount >= average * Reports::Thresholds::LARGE_TRANSACTION_RATIO

    [ {
      rule: :large_transaction, kind: "anomaly",
      message: I18n.t("reports.insights.large_transaction", amount: MoneyFormat.number(amount), name: name_for(category_id)),
      category_id: category_id,
      data: { transaction_id: id, amount: amount.to_d, description: description, average: average.to_d }
    } ]
  end

  def transaction_count_unusual
    current = filter.expense_scope(period.range).where.missing(:payments).count
    history = monthly_history_counts
    return [] if history.empty?

    average = history.sum / history.size
    return [] if average.zero? || current < average * Reports::Thresholds::TRANSACTION_COUNT_RATIO

    [ {
      rule: :transaction_count_unusual, kind: "anomaly",
      message: I18n.t("reports.insights.transaction_count_unusual", count: current),
      data: { count: current, historical_monthly_average: average }
    } ]
  end

  def credit_utilization_increase
    Reports::CreditCards.new(user: user, filter: filter).call[:cards]
                        .select { |card| card[:utilization_pct].to_d >= Reports::Thresholds::HIGH_UTILIZATION_PCT }
                        .select { |card| card[:purchases].to_d > card[:payments].to_d }
                        .map do |card|
      {
        rule: :credit_utilization_increase, kind: "anomaly",
        message: I18n.t("reports.insights.credit_utilization_increase", name: card[:name],
                        pct: card[:utilization_pct]),
        data: { card_id: card[:id], utilization_pct: card[:utilization_pct],
                purchases: card[:purchases], payments: card[:payments] }
      }
    end
  end

  def recurring_commitment_increase
    recurring = Reports::Recurring.new(user: user, filter: filter).call
    today = recurring[:monthly_committed]
    processed_last_month = Transaction.for_user(user).expense
                                      .where.not(recurring_template_id: nil)
                                      .where(date: period.previous_range)
                                      .sum(Arel.sql("ABS(amount)")).to_d
    increase = today - processed_last_month
    return [] if today.zero? || increase < today * Reports::Thresholds::RECURRING_INCREASE_PCT / 100

    [ {
      rule: :recurring_commitment_increase, kind: "increase",
      message: I18n.t("reports.insights.recurring_commitment_increase", amount: MoneyFormat.currency(increase)),
      data: { monthly_committed: today, processed_last_month: processed_last_month, increase: increase }
    } ]
  end

  def debt_payment_increase
    current = debt_total(period.range)
    previous = debt_total(period.previous_range)
    pct = integer_pct(current, previous)
    return [] if pct.nil? || pct < Reports::Thresholds::DEBT_PAYMENT_SPIKE_PCT

    [ {
      rule: :debt_payment_increase, kind: "increase",
      message: I18n.t("reports.insights.debt_payment_increase", pct: pct),
      data: { total: current, previous: previous, delta_pct: pct }
    } ]
  end

  # --- helpers ---

  def actual_total(range)
    filter.expense_scope(range).where.missing(:payments)
          .sum(Arel.sql("ABS(transactions.amount)")).to_d
  end

  def debt_total(range)
    Payment.for_user(user)
           .where(date: range)
           .where("exists (?)", filter.expense_scope(range).select(:id))
           .sum(Arel.sql("amount")).to_d +
      filter.transfer_scope(range)
            .where("to_source_id IN (?)", MoneySource.debt_payment_targets.select(:id))
            .where("from_source_id NOT IN (?)", MoneySource.debt_payment_targets.select(:id))
            .sum(:amount).to_d
  end

  def grouped_categories(range)
    filter.expense_scope(range).where.missing(:payments)
          .group(:category_id)
          .pluck(Arel.sql("transactions.category_id"), Arel.sql("ABS(SUM(transactions.amount))"),
                 Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT date_trunc('month', transactions.date))"))
          .index_by { |category_id, *_rest| category_id }
          .transform_values do |_category_id, total, count, months|
      { total: total.to_d, count: count.to_i, months: months.to_i, name: name_for(_category_id) }
    end
  end

  def monthly_history_counts
    period_start = period.range.begin
    (1..HISTORICAL_MONTHS).map do |offset|
      window_start = period_start - offset.months
      window = window_start.beginning_of_month..window_start.end_of_month
      filter.expense_scope(window).where.missing(:payments).count
    end
  end

  def history_range
    period.range.begin - HISTORICAL_MONTHS.months..period.range.begin - 1.day
  end

  def integer_pct(current, previous)
    return nil if previous.to_d.zero?

    ((current.to_d - previous.to_d) / previous.to_d * 100).round
  end

  def name_for(category_id)
    return I18n.t("reports.uncategorized", default: "Sin categoría") if category_id.blank?

    @category_names ||= {}
    @category_names[category_id] ||= Category.find_by(id: category_id)&.name ||
                                     I18n.t("reports.uncategorized", default: "Sin categoría")
  end
end
