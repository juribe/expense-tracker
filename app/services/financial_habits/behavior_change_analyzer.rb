# frozen_string_literal: true

module FinancialHabits
  class BehaviorChangeAnalyzer
    MIN_MONTHS = 2
    THRESHOLD_PCT = 20

    attr_reader :user, :range

    def initialize(user:, window: nil, date: nil, range: nil, start_date: nil, end_date: nil)
      @user = user
      @range = resolve_range(user, window: window, date: date, range: range,
                             start_date: start_date, end_date: end_date)
    end

    def call
      expenses = base_expenses.to_a
      by_month = expenses.group_by { |expense| expense.date.beginning_of_month }
                         .transform_values { |items| items.sum { |e| e.amount.to_d.abs } }

      months = by_month.keys.sort
      detected = months.size >= MIN_MONTHS

      current_month = months.last
      current_total = by_month[current_month] || 0.to_d
      historical_totals = months[0...-1].map { |month| by_month[month] }
      historical_average = historical_totals.any? ? (historical_totals.sum / historical_totals.size) : 0.to_d
      delta_pct = historical_average.positive? ? ((current_total - historical_average) / historical_average * 100).round : 0

      detected = detected && delta_pct.abs >= THRESHOLD_PCT

      score = 0
      if detected
        score = 40
        score += 15 if months.size >= 3
        score += 10 if expenses.size >= 10
        score += 10 if delta_pct.abs >= 35
        score = [score, 100].min
      end
      confidence = level_for(score) if detected

      direction = delta_pct.positive? ? "aumentado" : "disminuido"
      title = "Tus gastos están cambiando."
      description = "Durante el último periodo, tus gastos han #{direction} frente a tu comportamiento habitual."

      discovery = if detected
        {
          key: "behavior_change",
          type: "behavior_change",
          rule: :behavior_change,
          title: title,
          description: description,
          evidence: {
            current_month: current_month,
            current_total: current_total.round(2),
            historical_average: historical_average.round(2),
            delta_pct: delta_pct,
            months_observed: months.size
          },
          quantitative_evidence: {
            delta_pct: delta_pct,
            months_observed: months.size
          },
          period: period_label,
          period_analyzed: period_label,
          confidence: confidence,
          confidence_level: confidence,
          confidence_score: score,
          confidence_text: confidence_text(confidence),
          recommendation: "Revisa qué cambió en tus gastos recientes para decidir si es algo temporal o una nueva rutina.",
          action: { label: "Ver reportes", path: "/reports/trends" },
          action_label: "Ver reportes",
          available: true,
          detected: true
        }
      end

      {
        analyzer: "behavior_change",
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
          months_observed: months.size,
          current_total: current_total.round(2),
          historical_average: historical_average.round(2),
          delta_pct: delta_pct
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

BehaviorChangeAnalyzer = FinancialHabits::BehaviorChangeAnalyzer unless defined?(BehaviorChangeAnalyzer)