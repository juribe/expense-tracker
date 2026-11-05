# frozen_string_literal: true

module FinancialHabits
  class CreditUsagePatternAnalyzer
    MIN_TRANSACTIONS = 5
    THRESHOLD_PCT = 30

    attr_reader :user, :range

    def initialize(user:, window: nil, date: nil, range: nil, start_date: nil, end_date: nil)
      @user = user
      @range = resolve_range(user, window: window, date: date, range: range,
                             start_date: start_date, end_date: end_date)
    end

    def call
      expenses = base_expenses.to_a
      credit_expenses = expenses.select { |expense| expense.money_source&.credit_card? }

      total = expenses.sum { |expense| expense.amount.to_d.abs }
      credit_total = credit_expenses.sum { |expense| expense.amount.to_d.abs }
      pct = total.positive? ? (credit_total / total * 100).round : 0

      categories = credit_expenses.group_by { |expense| expense.category&.name || "Sin categoría" }
                                 .map do |name, group|
        {
          name: name,
          count: group.size,
          total: group.sum { |expense| expense.amount.to_d.abs }.round(2)
        }
      end.sort_by { |row| -row[:total] }

      distinct_months = credit_expenses.map { |expense| expense.date.beginning_of_month }.uniq.size

      detected = credit_expenses.size >= MIN_TRANSACTIONS && pct >= THRESHOLD_PCT

      score = 0
      if detected
        score = 35
        score += 15 if credit_expenses.size >= 10
        score += 10 if pct >= 40
        score += 10 if distinct_months >= 2
        score += 10 if categories.size >= 2
        score = [score, 100].min
      end
      confidence = level_for(score) if detected

      discovery = if detected
        {
          key: "credit_usage_pattern",
          type: "credit_usage_pattern",
          rule: :credit_usage_pattern,
          title: "El crédito también está financiando tus gastos del día a día.",
          description: "Durante el periodo analizado, una parte de tus compras cotidianas se realizó con tarjeta de crédito.",
          evidence: {
            credit_expenses_count: credit_expenses.size,
            credit_total: credit_total.round(2),
            total_expenses: total.round(2),
            credit_pct: pct,
            categories: categories,
            distinct_months: distinct_months
          },
          quantitative_evidence: {
            credit_pct: pct,
            credit_expenses_count: credit_expenses.size
          },
          period: period_label,
          period_analyzed: period_label,
          confidence: confidence,
          confidence_level: confidence,
          confidence_score: score,
          confidence_text: confidence_text(confidence),
          recommendation: "Puedes revisar qué gastos cotidianos podrías cubrir con dinero disponible para evitar acumular consumos en tu tarjeta.",
          action: { label: "Ver tarjetas", path: "/money_sources/credit_cards" },
          action_label: "Ver tarjetas",
          available: true,
          detected: true
        }
      end

      {
        analyzer: "credit_usage_pattern",
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
          credit_expenses_count: credit_expenses.size,
          credit_total: credit_total.round(2),
          total_expenses: total.round(2),
          credit_pct: pct,
          categories: categories,
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

CreditUsagePatternAnalyzer = FinancialHabits::CreditUsagePatternAnalyzer unless defined?(CreditUsagePatternAnalyzer)