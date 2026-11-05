# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::CategoryAnalysis
  # Deterministic category-level savings opportunities. Compares the current
  # (partial) period against the equivalent elapsed days of the last three
  # complete periods, so an unfinished month is never compared with a full
  # one. Debt payments are excluded, exactly as in the reports section.
  #
  # Methods: call
  #
  # Example: SavingsOpportunities::CategoryAnalysis.new(user:, window:).call[:opportunities]
  class CategoryAnalysis
    INCREASE_THRESHOLD_PCT = 15.0
    SIGNIFICANT_SHARE_PCT = 15.0
    NEW_CATEGORY_SHARE_PCT = 10.0
    DEFAULT_REDUCTION_PCT = 10.to_d
    MAX_OPPORTUNITIES = 6
    QUICK_PERCENTAGES = [ 5, 10, 15, 20 ].freeze

    attr_reader :user, :window

    def initialize(user:, window:)
      @user = user
      @window = window
    end

    def call
      current = grouped(window.current_range)
      total = current.sum { |_id, row| row[:total] }
      complete = window.complete_ranges.map { |range| grouped(range) }
      comparable = window.comparable_ranges.map { |range| grouped(range) }
      series = window.complete_ranges.last(Window::SERIES_PERIODS).each_with_index.map do |range, index|
        { range: range, rows: complete[index + 1], label: window.series_labels[index] }
      end
      series << { range: window.current_range, rows: current, label: window.series_labels.last }

      categories = load_categories(current.keys.compact)
      all_rows = current.map do |category_id, row|
        build_row(category_id, row, total, complete, comparable, series, categories)
      end.sort_by { |row| -row[:current] }

      comparison_available = complete.any? { |rows| rows.any? { |_id, row| row[:total].positive? } }
      opportunities = comparison_available ? all_rows.select { |row| opportunity?(row) } : []

      {
        comparison_available: comparison_available,
        total: total,
        all_rows: all_rows,
        opportunities: opportunities.sort_by { |row| -row[:potential] }.first(MAX_OPPORTUNITIES)
      }
    end

    private

    # GMF (4x1.000) charges are a bank tax generated from other movements,
    # not a spending habit the user can reduce, so they never become an
    # opportunity.
    def grouped(range)
      scope = Expense.for_user(user).where(date: range).where.missing(:payments)
                     .where(gmf_origin_type: nil)

      scope.left_joins(:category)
           .group("categories.id", "categories.name")
           .pluck(Arel.sql("categories.id"), Arel.sql("categories.name"),
                  Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
           .each_with_object({}) do |(category_id, name, total, count), rows|
        rows[category_id] = { id: category_id, name: name, total: total.to_d, count: count.to_i }
      end
    end

    def load_categories(ids)
      return {} if ids.empty?

      Category.for_user(user).where(id: ids).includes(:saving_tips).index_by(&:id)
    end

    def build_row(category_id, row, total, complete, comparable, series, categories)
      category = categories[category_id]
      current = row[:total]
      comparable_average = average(comparable.map { |rows| rows.dig(category_id, :total) })
      previous_average = average(complete.map { |rows| rows.dig(category_id, :total) })
      suggested = category&.suggested_savings_percentage&.to_d || 0.to_d
      suggested = DEFAULT_REDUCTION_PCT unless suggested.positive?

      {
        id: category_id || "uncategorized",
        category_id: category_id,
        name: row[:name].presence || I18n.t("reports.uncategorized", default: "Sin categoría"),
        current: current,
        previous_average: previous_average,
        comparable_average: comparable_average,
        delta_pct: Reports::Base.delta_pct(current, comparable_average),
        share_pct: share_pct(current, total),
        count: row[:count],
        suggested_percentage: suggested,
        potential: (current * suggested / 100).round(2),
        quick_steps: QUICK_PERCENTAGES.index_with { |percentage| (current * percentage / 100).round },
        tip: first_tip(category),
        months: series.map do |entry|
          {
            label: entry[:label],
            total: entry[:rows].dig(category_id, :total) || 0.to_d,
            current: entry[:range] == window.current_range
          }
        end
      }
    end

    def average(totals)
      (totals.sum(0.to_d) { |value| value.to_d } / window.complete_ranges.size).round(2)
    end

    def share_pct(part, total)
      return 0.0 if total.zero?

      (part / total * 100).round(1)
    end

    def opportunity?(row)
      return false unless row[:current].positive?
      return true if row[:share_pct] >= SIGNIFICANT_SHARE_PCT

      if row[:comparable_average].positive?
        row[:delta_pct].to_f >= INCREASE_THRESHOLD_PCT
      else
        row[:share_pct] >= NEW_CATEGORY_SHARE_PCT
      end
    end

    def first_tip(category)
      return nil if category.nil?

      category.saving_tips.select(&:active?).min_by { |tip| [ tip.position.to_i, tip.created_at ] }&.body
    end
  end
end
