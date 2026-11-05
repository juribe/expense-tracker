# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::SmallExpenses
  # Finds frequent low-value purchases whose accumulated amount matters.
  # There is no fixed amount threshold: the cut is the largest relative gap in
  # the user's own transaction amounts, so "small" adapts to each person.
  #
  # Methods: call
  #
  # Example: SavingsOpportunities::SmallExpenses.new(user:, window:).call[:groups]
  class SmallExpenses
    MIN_MOVEMENTS = 5
    MIN_GROUP_OCCURRENCES = 2
    # A 50% jump between consecutive amounts is enough to separate a small
    # purchase cluster from the rest of the user's spending.
    MIN_SEPARATION_RATIO = 1.5
    MAX_GROUPS = 6
    MOVEMENTS_LIMIT = 5
    STOPWORDS = RecurringDetection::STOPWORDS

    attr_reader :user, :window

    def initialize(user:, window:)
      @user = user
      @window = window
    end

    def call
      return unavailable if expenses.size < MIN_MOVEMENTS

      threshold = adaptive_threshold
      return unavailable if threshold.nil?

      small = expenses.select { |expense| expense.amount.to_d.abs <= threshold }
      groups = group_small(small)
      return unavailable if groups.empty?

      total = groups.sum(0.to_d) { |group| group[:total] }
      count = groups.sum { |group| group[:count] }

      {
        available: true,
        total: total,
        count: count,
        average: (total / count).round(2),
        threshold: threshold,
        groups: groups,
        by_category: by_category(groups),
        top_weekday: top_weekday(small)
      }
    end

    private

    def unavailable
      {
        available: false,
        total: 0.to_d,
        count: 0,
        average: 0.to_d,
        threshold: nil,
        groups: [],
        by_category: [],
        top_weekday: nil
      }
    end

    def expenses
      @expenses ||= Expense.for_user(user)
                           .where(date: window.current_range)
                           .where.missing(:payments)
                           .where(gmf_origin_type: nil)
                           .order(date: :desc, created_at: :desc)
                           .to_a
    end

    # The cut is the lowest natural gap that leaves enough repeated low-value
    # movements. Candidates that only isolate one-off amounts (for example a
    # cluster of tiny placeholder charges) are skipped, so they cannot hide the
    # real small-purchase pattern.
    def adaptive_threshold
      amounts = expenses.map { |expense| expense.amount.to_d.abs }
      unique = amounts.uniq.sort
      return nil if unique.size < 2

      candidates = unique.each_cons(2).filter_map do |low, high|
        low if high / low >= MIN_SEPARATION_RATIO
      end

      candidates.sort.find { |threshold| repeated_movement_count(threshold) >= MIN_MOVEMENTS }
    end

    def repeated_movement_count(threshold)
      expenses.select { |expense| expense.amount.to_d.abs <= threshold }
              .group_by { |expense| normalize(expense.description) }
              .sum do |key, group|
                key.present? && group.size >= MIN_GROUP_OCCURRENCES ? group.size : 0
              end
    end

    def group_small(small)
      small.group_by { |expense| normalize(expense.description) }
           .filter_map do |key, group|
        next if key.blank? || group.size < MIN_GROUP_OCCURRENCES

        total = group.sum(0.to_d) { |expense| expense.amount.to_d.abs }
        {
          key: key,
          name: group.first.description.to_s.strip.presence ||
            I18n.t("savings_opportunities.small_expenses.unknown_concept"),
          total: total,
          count: group.size,
          average: (total / group.size).round(2),
          category_name: category_names[group.first.category_id] ||
            I18n.t("reports.uncategorized", default: "Sin categoría"),
          movements: movements(group)
        }
      end.sort_by { |group| -group[:total] }.first(MAX_GROUPS)
    end

    def movements(group)
      group.first(MOVEMENTS_LIMIT).map do |expense|
        {
          id: expense.id,
          date: expense.date,
          amount: expense.amount.to_d.abs,
          description: expense.description
        }
      end
    end

    def category_names
      @category_names ||= Category.for_user(user)
                                  .where(id: expenses.filter_map(&:category_id).uniq)
                                  .pluck(:id, :name)
                                  .to_h
    end

    def by_category(groups)
      totals = Hash.new { |hash, key| hash[key] = { name: key, total: 0.to_d, count: 0 } }
      groups.each do |group|
        entry = totals[group[:category_name]]
        entry[:total] += group[:total]
        entry[:count] += group[:count]
      end
      totals.values.sort_by { |row| -row[:total] }
    end

    def top_weekday(small)
      counts = small.group_by { |expense| expense.date.wday }.transform_values(&:size)
      counts.max_by { |_weekday, count| count }&.first
    end

    def normalize(description)
      text = ActiveSupport::Inflector.transliterate(description.to_s).downcase
      text = text.gsub(%r{\b\d{1,2}[/.-]\d{1,2}([/.-]\d{2,4})?\b}, " ")
      text = text.gsub(/\b\d{3,}\b/, " ")
      text = text.gsub(/[^a-z0-9\s]/, " ")
      text.split.reject { |word| word.match?(/\A\d+\z/) || STOPWORDS.include?(word) }
          .join(" ").squeeze(" ").strip
    end
  end
end
