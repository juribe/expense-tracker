# frozen_string_literal: true

module FinancialHabits
  # FinancialHabits::Analysis
  # Coordinator that runs all financial habit analyzers and aggregates their
  # discoveries.
  class Analysis
    attr_reader :user, :range

    def initialize(user:, date: Date.current, window: nil, range: nil, start_date: nil, end_date: nil)
      @user = user
      @range = resolve_range(user, window: window, date: date, range: range,
                             start_date: start_date, end_date: end_date)
    end

    def call
      analyzers = [
        IncomeSpendingPatternAnalyzer.new(user: user, range: range),
        SpendingTimePatternAnalyzer.new(user: user, range: range),
        MerchantFrequencyAnalyzer.new(user: user, range: range),
        CreditUsagePatternAnalyzer.new(user: user, range: range),
        CycleEndSpendingAnalyzer.new(user: user, range: range),
        BehaviorChangeAnalyzer.new(user: user, range: range),
        PlanningOpportunityAnalyzer.new(user: user, range: range)
      ]

      analyzer_results = analyzers.map(&:call)
      discoveries = analyzer_results.flat_map { |result| Array(result[:discoveries]) }

      expenses_count = base_expenses_count
      incomes_count = base_incomes_count
      total_movements = expenses_count + incomes_count

      state = if total_movements.zero?
        :empty
      elsif total_movements < 5
        :insufficient_data
      else
        :ok
      end

      time_data_available = analyzer_results[1][:time_data_available]

      {
        user_id: user.id,
        state: state,
        generated_at: Time.current.iso8601,
        fingerprint: fingerprint(expenses_count, incomes_count),
        period: range,
        period_label: "#{range.begin} - #{range.end}",
        window_label: "#{range.begin} - #{range.end}",
        analyzed_movements: total_movements,
        movements_count: total_movements,
        expenses_count: expenses_count,
        incomes_count: incomes_count,
        time_data_available: time_data_available,
        discoveries: discoveries,
        habits: discoveries,
        insights: discoveries,
        patterns: discoveries,
        results: analyzer_results,
        analyzers: analyzer_results,
        analyzer_results: analyzer_results,
        state_text: state_text(state)
      }
    end

    private

    def base_expenses_count
      Expense.for_user(user).where(date: range).where.missing(:payments).where(gmf_origin_type: nil).count
    end

    def base_incomes_count
      Income.for_user(user).where(date: range).count
    end

    def fingerprint(expenses_count, incomes_count)
      expense_latest = Expense.for_user(user).maximum(:updated_at)&.to_f
      income_latest = Income.for_user(user).maximum(:updated_at)&.to_f
      Digest::SHA256.hexdigest(
        [user.id, expenses_count, incomes_count, expense_latest, income_latest, Date.current].join(":")
      )
    end

    def state_text(state)
      case state
      when :empty then "empty"
      when :insufficient_data then "insufficient"
      else "ok"
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

# Compatibility aliases
FinancialHabitsService = FinancialHabits::Analysis unless defined?(FinancialHabitsService)
FinancialHabitsAnalyzer = FinancialHabits::Analysis unless defined?(FinancialHabitsAnalyzer)