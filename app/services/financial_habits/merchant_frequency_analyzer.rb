# frozen_string_literal: true

module FinancialHabits
  class MerchantFrequencyAnalyzer
    MIN_VISITS = 3
    MAX_MERCHANTS = 5

    attr_reader :user, :range

    def initialize(user:, window: nil, date: nil, range: nil, start_date: nil, end_date: nil)
      @user = user
      @range = resolve_range(user, window: window, date: date, range: range,
                             start_date: start_date, end_date: end_date)
    end

    def call
      expenses = base_expenses.to_a
      groups = expenses.group_by { |expense| normalize(expense.description) }

      merchants = groups.filter_map do |key, group|
        next if key.blank?

        dates = group.map(&:date).uniq.sort
        next if dates.size < 2
        next if group.size < MIN_VISITS

        total = group.sum { |expense| expense.amount.to_d.abs }
        intervals = dates.each_cons(2).map { |a, b| (b - a).to_i }
        avg_interval = intervals.any? ? (intervals.sum.to_f / intervals.size).round(1) : nil

        {
          key: key,
          name: group.first.description.to_s.strip.presence || key,
          visits: group.size,
          distinct_days: dates.size,
          total: total.round(2),
          average_amount: (total / group.size).round(2),
          average_interval_days: avg_interval
        }
      end.sort_by { |merchant| -merchant[:visits] }.first(MAX_MERCHANTS)

      detected = merchants.any?
      score = 0
      if detected
        score = 40
        score += [merchants.size, 3].min * 10
        score += 10 if merchants.first[:visits] >= 5
        distinct_months = expenses.map { |expense| expense.date.beginning_of_month }.uniq.size
        score += 10 if distinct_months >= 2
        score = [score, 100].min
      end
      confidence = level_for(score) if detected

      discovery = if detected
        {
          key: "merchant_frequency",
          type: "merchant_frequency",
          rule: :merchant_frequency,
          title: "Hay lugares que forman parte de tu rutina.",
          description: "Has realizado pagos en determinados establecimientos varias veces durante el periodo analizado.",
          evidence: {
            merchants_count: merchants.size,
            merchants: merchants,
            top_merchant: merchants.first[:name],
            top_visits: merchants.first[:visits],
            top_total: merchants.first[:total]
          },
          quantitative_evidence: {
            merchants_count: merchants.size,
            top_visits: merchants.first[:visits]
          },
          period: period_label,
          period_analyzed: period_label,
          confidence: confidence,
          confidence_level: confidence,
          confidence_score: score,
          confidence_text: confidence_text(confidence),
          recommendation: "Revisar estos gastos puede ayudarte a entender cuánto representan estos hábitos dentro de tu presupuesto.",
          action: { label: "Ver gastos", path: "/expenses" },
          action_label: "Ver gastos",
          available: true,
          detected: true
        }
      end

      {
        analyzer: "merchant_frequency",
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
          merchants_count: merchants.size,
          merchants: merchants,
          min_visits: MIN_VISITS
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

MerchantFrequencyAnalyzer = FinancialHabits::MerchantFrequencyAnalyzer unless defined?(MerchantFrequencyAnalyzer)