# frozen_string_literal: true

module FinancialHabits
  # FinancialHabits::CycleEndSpendingAnalyzer
  # Detects whether expenses concentrate in the last five days of a complete
  # income cycle (from one income date to the day before the next one).
  class CycleEndSpendingAnalyzer
    MIN_EXPENSES = 5
    LAST_DAYS = 5
    THRESHOLD_PCT = 35

    attr_reader :user, :range

    def initialize(user:, window: nil, date: nil, range: nil, start_date: nil, end_date: nil)
      @user = user
      @range = resolve_range(user, window: window, date: date, range: range,
                             start_date: start_date, end_date: end_date)
    end

    def call
      incomes = base_incomes.to_a.sort_by(&:date)
      expenses = base_expenses.to_a
      cycles = build_cycles(incomes, expenses)

      detected = cycles.size >= 2 && expenses.size >= MIN_EXPENSES &&
                 cycles.any? { |cycle| cycle[:last_days_pct] >= THRESHOLD_PCT }

      score = 0
      if detected
        score = 35
        score += 15 if cycles.size >= 3
        score += 10 if expenses.size >= 10
        score += 10 if cycles.count { |cycle| cycle[:last_days_pct] >= THRESHOLD_PCT } >= 2
        score = [score, 100].min
      end
      confidence = level_for(score) if detected

      total_last_days = cycles.sum { |cycle| cycle[:last_days_total] }
      total_all = cycles.sum { |cycle| cycle[:total] }
      overall_pct = total_all.positive? ? (total_last_days / total_all * 100).round : 0

      discovery = if detected
        {
          key: "cycle_end_spending",
          type: "cycle_end_spending",
          rule: :cycle_end_spending,
          title: "Así se comportan tus gastos antes de recibir nuevos ingresos.",
          description: "Analizamos cómo distribuyes tus gastos durante los últimos días de tus ciclos de ingresos.",
          evidence: {
            last_days: LAST_DAYS,
            last_days_pct: overall_pct,
            last_days_total: total_last_days.round(2),
            cycles_observed: cycles.size,
            cycles: cycles
          },
          quantitative_evidence: {
            last_days_pct: overall_pct,
            cycles_observed: cycles.size
          },
          period: period_label,
          period_analyzed: period_label,
          confidence: confidence,
          confidence_level: confidence,
          confidence_score: score,
          confidence_text: confidence_text(confidence),
          recommendation: "Podrías revisar qué gastos suelen aparecer al final del ciclo y anticipar aquellos que puedas planificar desde el comienzo del mes.",
          action: { label: "Ver análisis", path: "/financial_habits/cycle_end_spending" },
          action_label: "Ver análisis",
          available: true,
          detected: true
        }
      end

      {
        analyzer: "cycle_end_spending",
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
          cycles_observed: cycles.size,
          last_days_pct: overall_pct,
          last_days_total: total_last_days.round(2),
          cycles: cycles
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

    def build_cycles(incomes, expenses)
      incomes.each_with_index.filter_map do |income, index|
        next_income = incomes[index + 1]
        next unless next_income

        cycle_start = income.date
        cycle_end = next_income.date - 1.day
        next if cycle_end < cycle_start

        cycle_expenses = expenses.select { |expense| expense.date.between?(cycle_start, cycle_end) }
        total = cycle_expenses.sum { |expense| expense.amount.to_d.abs }
        next if total.zero?

        last_start = [ cycle_end - (LAST_DAYS - 1), cycle_start ].max
        last_total = cycle_expenses.select { |expense| expense.date.between?(last_start, cycle_end) }
                                   .sum { |expense| expense.amount.to_d.abs }
        {
          start_date: cycle_start,
          end_date: cycle_end,
          income_date: income.date,
          total: total.round(2),
          last_days_total: last_total.round(2),
          last_days_pct: (last_total / total * 100).round
        }
      end
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

CycleEndSpendingAnalyzer = FinancialHabits::CycleEndSpendingAnalyzer unless defined?(CycleEndSpendingAnalyzer)