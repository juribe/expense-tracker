# frozen_string_literal: true

module FinancialHabits
  class PlanningOpportunityAnalyzer
    MIN_OCCURRENCES = 3
    MAX_AMOUNT_SPREAD = 0.25
    MIN_INTERVAL = 25
    MAX_INTERVAL = 40
    MAX_PATTERNS = 5

    attr_reader :user, :range

    def initialize(user:, window: nil, date: nil, range: nil, start_date: nil, end_date: nil)
      @user = user
      @range = resolve_range(user, window: window, date: date, range: range,
                             start_date: start_date, end_date: end_date)
    end

    def call
      expenses = base_expenses.to_a
      groups = expenses.group_by { |expense| normalize(expense.description) }

      patterns = groups.filter_map do |key, group|
        next if key.blank?

        dates = group.map(&:date).uniq.sort
        next if dates.size < MIN_OCCURRENCES

        amounts = group.map { |expense| expense.amount.to_d.abs }
        median_amount = median(amounts)
        next unless median_amount.positive?

        spread = (amounts.max - amounts.min) / median_amount
        next if spread > MAX_AMOUNT_SPREAD

        intervals = dates.each_cons(2).map { |a, b| (b - a).to_i }
        median_interval = median(intervals)
        next unless median_interval.between?(MIN_INTERVAL, MAX_INTERVAL)

        {
          key: key,
          name: group.first.description.to_s.strip.presence || key,
          occurrences: dates.size,
          average_amount: median_amount.round(2),
          interval_days: median_interval.round
        }
      end.sort_by { |pattern| -pattern[:occurrences] }.first(MAX_PATTERNS)

      detected = patterns.any?
      score = 0
      if detected
        score = 45
        score += 15 if patterns.size >= 2
        score += 10 if patterns.first[:occurrences] >= 4
        score = [score, 100].min
      end
      confidence = level_for(score) if detected

      discovery = if detected
        {
          key: "planning_opportunity",
          type: "planning_opportunity",
          rule: :planning_opportunity,
          title: "Hay gastos que podrías anticipar mejor.",
          description: "Identificamos pagos que se repiten con cierta regularidad y podrían planificarse con anticipación.",
          evidence: {
            patterns_count: patterns.size,
            patterns: patterns
          },
          quantitative_evidence: {
            patterns_count: patterns.size
          },
          period: period_label,
          period_analyzed: period_label,
          confidence: confidence,
          confidence_level: confidence,
          confidence_score: score,
          confidence_text: confidence_text(confidence),
          recommendation: "Podrías registrarlos como pagos planificados para evitar sorpresas al final del mes.",
          action: { label: "Ver recurrentes", path: "/recurring_templates" },
          action_label: "Ver recurrentes",
          available: true,
          detected: true
        }
      end

      {
        analyzer: "planning_opportunity",
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
          patterns_count: patterns.size,
          patterns: patterns
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

    def normalize(description)
      text = ActiveSupport::Inflector.transliterate(description.to_s).downcase
      text = text.gsub(%r{\b\d{1,2}[/.-]\d{1,2}([/.-]\d{2,4})?\b}, " ")
      text = text.gsub(/\b\d{3,}\b/, " ")
      text = text.gsub(/[^a-z0-9\s]/, " ")
      text.split.reject { |word| word.match?(/\A\d+\z/) }.join(" ").squeeze(" ").strip
    end

    def median(values)
      sorted = values.sort
      sorted[sorted.size / 2]
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

PlanningOpportunityAnalyzer = FinancialHabits::PlanningOpportunityAnalyzer unless defined?(PlanningOpportunityAnalyzer)