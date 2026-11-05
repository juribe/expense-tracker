# frozen_string_literal: true

module FinancialHabits
  # FinancialHabits::IncomeSpendingPatternAnalyzer
  # Detects whether a significant share of expenses concentrates in the first
  # days after an income is received.
  class IncomeSpendingPatternAnalyzer
    MIN_EXPENSES = 5
    POST_WINDOW_DAYS = 5
    THRESHOLD_PCT = 35

    attr_reader :user, :range

    def initialize(user:, window: nil, date: nil, range: nil, start_date: nil, end_date: nil)
      @user = user
      @range = resolve_range(user, window: window, date: date, range: range,
                             start_date: start_date, end_date: end_date)
    end

    def call
      expenses = base_expenses.to_a
      incomes = base_incomes.to_a

      total = expenses.sum { |expense| expense.amount.to_d.abs }
      post_expenses = expenses.select do |expense|
        incomes.any? { |income| (expense.date - income.date).to_i.between?(0, POST_WINDOW_DAYS) }
      end
      post_total = post_expenses.sum { |expense| expense.amount.to_d.abs }
      pct = total.positive? ? (post_total / total * 100).round : 0

      distinct_months = expenses.map { |expense| expense.date.beginning_of_month }.uniq.size
      cycles = incomes.size

      detected = incomes.any? && expenses.size >= MIN_EXPENSES && pct >= THRESHOLD_PCT

      score = 0
      if detected
        score = 30
        score += [cycles, 3].min * 15
        score += 10 if expenses.size >= 10
        score += 10 if pct >= 50
        score += 10 if distinct_months >= 2
        score = [score, 100].min
      end

      confidence = level_for(score) if detected

      discovery = if detected
        {
          key: "income_spending_pattern",
          type: "income_spending_pattern",
          rule: :income_spending_pattern,
          title: "Tus gastos aumentan después de recibir ingresos.",
          description: "Durante los últimos meses, una parte importante de tus gastos se concentra en los primeros días después de recibir dinero.",
          evidence: {
            post_window_days: POST_WINDOW_DAYS,
            post_window_expenses_count: post_expenses.size,
            post_window_total: post_total.round(2),
            total_expenses: total.round(2),
            post_window_pct: pct,
            incomes_count: incomes.size,
            cycles_observed: cycles,
            distinct_months: distinct_months
          },
          quantitative_evidence: {
            post_window_pct: pct,
            post_window_days: POST_WINDOW_DAYS,
            cycles_observed: cycles
          },
          period: period_label,
          period_analyzed: period_label,
          confidence: confidence,
          confidence_level: confidence,
          confidence_score: score,
          confidence_text: confidence_text(confidence),
          recommendation: "Podrías separar primero el dinero destinado a tus obligaciones y ahorro, antes de comenzar a utilizar el resto.",
          action: { label: "Ver gastos", path: "/expenses" },
          action_label: "Ver gastos",
          available: true,
          detected: true
        }
      end

      {
        analyzer: "income_spending_pattern",
        available: detected,
        detected: detected,
        discovery: discovery,
        discoveries: discovery ? [discovery] : [],
        title: discovery&.dig(:title),
        description: discovery&.dig(:description),
        evidence: discovery&.dig(:evidence),
        period: period_label,
        confidence: discovery&.dig(:confidence),
        confidence_level: discovery&.dig(:confidence),
        confidence_score: score,
        recommendation: discovery&.dig(:recommendation),
        action: discovery&.dig(:action),
        metrics: {
          post_window_days: POST_WINDOW_DAYS,
          post_window_expenses_count: post_expenses.size,
          post_window_total: post_total.round(2),
          total_expenses: total.round(2),
          post_window_pct: pct,
          incomes_count: incomes.size,
          cycles_observed: cycles,
          distinct_months: distinct_months,
          threshold_pct: THRESHOLD_PCT
        },
        reason: detected ? nil : "insufficient_or_no_pattern"
      }
    end

    private

    def base_expenses
      Expense.for_user(user)
             .where(date: range)
             .where.missing(:payments)
             .where(gmf_origin_type: nil)
             .includes(:money_source, :category)
    end

    def base_incomes
      Income.for_user(user).where(date: range)
    end

    def period_label
      "#{range.begin} - #{range.end}"
    end

    def level_for(score)
      return :high if score >= 70
      return :medium if score >= 45
      :low
    end

    def confidence_text(level)
      case level
      when :high then "alta"
      when :medium then "media"
      else "baja"
      end
    end

    def resolve_range(_user, window:, date:, range:, start_date:, end_date:)
      return range if range.is_a?(Range)
      if window && window.respond_to?(:recurring_range)
        window.recurring_range
      elsif start_date.present? && end_date.present?
        start_date.to_date..end_date.to_date
      elsif date.present?
        (date.to_date - 3.months).beginning_of_month..date.to_date
      else
        (Date.current - 3.months).beginning_of_month..Date.current
      end
    end
  end
end

# Top-level alias for compatibility with alternative naming.
IncomeSpendingPatternAnalyzer = FinancialHabits::IncomeSpendingPatternAnalyzer unless defined?(IncomeSpendingPatternAnalyzer)