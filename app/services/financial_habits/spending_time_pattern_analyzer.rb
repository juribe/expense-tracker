# frozen_string_literal: true

module FinancialHabits
  class SpendingTimePatternAnalyzer
    MIN_EXPENSES = 5
    THRESHOLD_PCT = 35

    SLOTS = [
      { key: "madrugada", label: "madrugada", range: 0..5 },
      { key: "manana", label: "mañana", range: 6..11 },
      { key: "tarde", label: "tarde", range: 12..17 },
      { key: "noche", label: "final del día", range: 18..23 }
    ].freeze

    attr_reader :user, :range

    def initialize(user:, window: nil, date: nil, range: nil, start_date: nil, end_date: nil)
      @user = user
      @range = resolve_range(user, window: window, date: date, range: range,
                             start_date: start_date, end_date: end_date)
    end

    def call
      expenses = base_expenses.to_a
      timed_expenses = expenses.select { |expense| reliable_time(expense).present? }
      time_data_available = timed_expenses.any?

      slot_counts = SLOTS.each_with_object({}) do |slot, hash|
        hash[slot[:key]] = { label: slot[:label], count: 0, total: 0.to_d }
      end

      timed_expenses.each do |expense|
        time = reliable_time(expense)
        slot = SLOTS.find { |candidate| candidate[:range].cover?(time.hour) }
        next unless slot

        slot_counts[slot[:key]][:count] += 1
        slot_counts[slot[:key]][:total] += expense.amount.to_d.abs
      end

      total_timed = timed_expenses.size
      peak = slot_counts.max_by { |_key, value| value[:count] }
      peak_key = peak&.first
      peak_count = peak&.last&.dig(:count) || 0
      peak_pct = total_timed.positive? ? (peak_count.to_f / total_timed * 100).round : 0
      peak_label = peak&.last&.dig(:label)

      distinct_months = timed_expenses.map { |expense| expense.date.beginning_of_month }.uniq.size

      hour_detected = time_data_available && total_timed >= MIN_EXPENSES && peak_pct >= THRESHOLD_PCT

      # Weekday concentration (always available from dates).
      weekday_counts = expenses.each_with_object(Hash.new(0)) { |expense, hash| hash[expense.date.wday] += 1 }
      total_expenses = expenses.size
      peak_wday = weekday_counts.max_by { |_wday, count| count }
      peak_wday_key = peak_wday&.first
      peak_wday_count = peak_wday&.last || 0
      peak_wday_pct = total_expenses.positive? ? (peak_wday_count.to_f / total_expenses * 100).round : 0
      weekday_detected = total_expenses >= MIN_EXPENSES && peak_wday_pct >= THRESHOLD_PCT
      weekday_names = %w[domingo lunes martes miércoles jueves viernes sábado]

      discoveries = []

      if hour_detected
        score = 35
        score += 15 if total_timed >= 10
        score += 10 if peak_pct >= 50
        score += 10 if distinct_months >= 2
        score = [score, 100].min
        confidence = level_for(score)

        title = peak_key == "noche" ? "Tus gastos se concentran al final del día." : "Tus gastos se concentran en la #{peak_label}."
        description = "Una parte importante de tus compras ocurre en la franja de #{peak_label}."

        discoveries << {
          key: "spending_time_pattern",
          type: "spending_time_pattern",
          rule: :spending_time_pattern,
          title: title,
          description: description,
          evidence: {
            peak_slot: peak_key,
            peak_slot_label: peak_label,
            peak_count: peak_count,
            peak_pct: peak_pct,
            total_timed_expenses: total_timed,
            slot_distribution: slot_counts.transform_values { |value| { count: value[:count], total: value[:total].round(2) } },
            distinct_months: distinct_months
          },
          quantitative_evidence: { peak_pct: peak_pct, peak_slot: peak_key },
          period: period_label,
          period_analyzed: period_label,
          confidence: confidence,
          confidence_level: confidence,
          confidence_score: score,
          confidence_text: confidence_text(confidence),
          recommendation: "Puedes revisar tus compras de esta franja para identificar cuáles responden a necesidades y cuáles podrías planificar con anticipación.",
          action: { label: "Ver gastos", path: "/expenses" },
          action_label: "Ver gastos",
          available: true,
          detected: true
        }
      end

      if weekday_detected
        score = 35
        score += 15 if total_expenses >= 10
        score += 10 if peak_wday_pct >= 50
        score = [score, 100].min
        confidence = level_for(score)

        day_name = weekday_names[peak_wday_key]
        title = "Tus gastos se concentran en ciertos días de la semana."
        description = "Una parte importante de tus movimientos ocurre los #{day_name}."

        discoveries << {
          key: "spending_weekday_pattern",
          type: "spending_weekday_pattern",
          rule: :spending_weekday_pattern,
          title: title,
          description: description,
          evidence: {
            peak_weekday: day_name,
            peak_weekday_count: peak_wday_count,
            peak_weekday_pct: peak_wday_pct,
            weekday_distribution: weekday_counts
          },
          quantitative_evidence: { peak_weekday_pct: peak_wday_pct, peak_weekday: day_name },
          period: period_label,
          period_analyzed: period_label,
          confidence: confidence,
          confidence_level: confidence,
          confidence_score: score,
          confidence_text: confidence_text(confidence),
          recommendation: "Puedes revisar si esos días concentran gastos planificables o impulsivos.",
          action: { label: "Ver gastos", path: "/expenses" },
          action_label: "Ver gastos",
          available: true,
          detected: true
        }
      end

      detected = discoveries.any?

      {
        analyzer: "spending_time_pattern",
        available: detected,
        detected: detected,
        discovery: discoveries.first,
        discoveries: discoveries,
        title: discoveries.first&.dig(:title),
        description: discoveries.first&.dig(:description),
        evidence: discoveries.first&.dig(:evidence),
        period: period_label,
        confidence: discoveries.first&.dig(:confidence),
        confidence_level: discoveries.first&.dig(:confidence),
        confidence_score: discoveries.first&.dig(:confidence_score) || 0,
        recommendation: discoveries.first&.dig(:recommendation),
        action: discoveries.first&.dig(:action),
        time_data_available: time_data_available,
        metrics: {
          total_expenses: expenses.size,
          timed_expenses: total_timed,
          peak_slot: peak_key,
          peak_pct: peak_pct,
          slot_distribution: slot_counts,
          peak_weekday: peak_wday_key,
          peak_weekday_pct: peak_wday_pct
        },
        reason: if !detected && !time_data_available && expenses.empty?
                  "missing_time_data"
                elsif !detected
                  "insufficient_or_no_pattern"
                end
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

    def reliable_time(expense)
      if expense.respond_to?(:occurred_at) && expense.occurred_at.is_a?(Time)
        expense.occurred_at
      elsif expense.respond_to?(:created_at) && expense.created_at.present? &&
            expense.created_at.to_date == expense.date
        expense.created_at
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

SpendingTimePatternAnalyzer = FinancialHabits::SpendingTimePatternAnalyzer unless defined?(SpendingTimePatternAnalyzer)