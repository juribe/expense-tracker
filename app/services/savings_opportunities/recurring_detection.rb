# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::RecurringDetection
  # Finds payment patterns in the user's real expenses by normalizing
  # descriptions, grouping similar amounts and measuring the interval between
  # payments. A pattern is only "confirmed" with consistent amounts and dates;
  # everything else is presented as a possible recurring payment for the user
  # to review. Nothing is cancelled or modified.
  #
  # Methods: call
  #
  # Example: SavingsOpportunities::RecurringDetection.new(user:, window:).call[:rows]
  class RecurringDetection
    MIN_OCCURRENCES = 3
    MAX_AMOUNT_SPREAD = 0.25
    CONFIRMED_AMOUNT_SPREAD = 0.10
    MAX_INTERVAL_DEVIATION = 0.35
    CONFIRMED_INTERVAL_DEVIATION = 0.20
    MAX_ROWS = 8
    MOVEMENTS_LIMIT = 5
    STOPWORDS = %w[de del la el los las y en pago compra com www co ltda sa sas].freeze
    MONTHLY_FACTORS = Reports::Recurring::MONTHLY_FACTORS

    attr_reader :user, :window, :scope

    # `scope` is optional and lets another report reuse the detection with its
    # own user/category/source filters. It must be an Expense relation; the
    # existing user scope remains the default.
    def initialize(user:, window:, scope: nil)
      @user = user
      @window = window
      @scope = scope
    end

    def call
      groups = expenses.group_by { |expense| normalize(expense.description) }
      rows = groups.filter_map { |key, group| build_row(key, group) }
                   .sort_by { |row| -row[:monthly_amount] }
                   .first(MAX_ROWS)

      {
        source: "movements",
        rows: rows,
        total_monthly: rows.sum(0.to_d) { |row| row[:monthly_amount] },
        confirmed_count: rows.count { |row| row[:confidence] == :confirmed },
        possible_count: rows.count { |row| row[:confidence] == :possible }
      }
    end

    private

    def expenses
      @expenses ||= source_scope
                           .where(date: window.recurring_range)
                           .where.missing(:payments)
                           .where(gmf_origin_type: nil)
                           .order(date: :desc, created_at: :desc)
                           .to_a
    end

    def source_scope
      scope || Expense.for_user(user)
    end

    def build_row(key, group)
      return nil if key.blank?

      dates = group.map(&:date).uniq.sort
      return nil if dates.size < MIN_OCCURRENCES

      amounts = group.map { |expense| expense.amount.to_d.abs }
      median_amount = median(amounts)
      return nil unless median_amount.positive?

      spread = (amounts.max - amounts.min) / median_amount
      return nil if spread > MAX_AMOUNT_SPREAD

      intervals = dates.each_cons(2).map { |previous_date, next_date| (next_date - previous_date).to_i }
      median_interval = median(intervals)
      frequency = frequency_for(median_interval)
      return nil if frequency.nil?

      deviation = intervals.map { |interval| (interval - median_interval).abs }.max.to_f / median_interval
      return nil if deviation > MAX_INTERVAL_DEVIATION

      {
        key: key,
        name: display_name(group),
        amount: median_amount.round(2),
        frequency: frequency,
        monthly_amount: monthly_equivalent(median_amount, frequency),
        last_date: dates.last,
        occurrences: dates.size,
        confidence: confidence_for(spread, deviation),
        movements: movements(group)
      }
    end

    def monthly_equivalent(amount, frequency)
      (amount.to_r * MONTHLY_FACTORS.fetch(frequency)).to_d.round(2)
    end

    def movements(group)
      group.first(MOVEMENTS_LIMIT).map do |expense|
        {
          id: expense.id,
          date: expense.date,
          amount: expense.amount.to_d.abs,
          description: expense.description,
          category_name: category_names[expense.category_id]
        }
      end
    end

    # Only the movements shown in the UI need their category name, so names are
    # resolved in one query for the whole detection instead of eager loading
    # every expense's associations.
    def category_names
      @category_names ||= Category.for_user(user)
                                  .where(id: expenses.filter_map(&:category_id).uniq)
                                  .pluck(:id, :name)
                                  .to_h
    end

    def confidence_for(spread, deviation)
      if spread <= CONFIRMED_AMOUNT_SPREAD && deviation <= CONFIRMED_INTERVAL_DEVIATION
        :confirmed
      else
        :possible
      end
    end

    def frequency_for(median_interval)
      case median_interval
      when 5..9 then "weekly"
      when 12..18 then "biweekly"
      when 25..40 then "monthly"
      when 80..100 then "quarterly"
      end
    end

    def display_name(group)
      group.first.description.to_s.strip.presence || I18n.t("savings_opportunities.recurring.unknown_merchant")
    end

    # Lowercase, strip references/dates and generic words so "NETFLIX.COM
    # 1234" and "netflix 12/09" land in the same group.
    def normalize(description)
      text = ActiveSupport::Inflector.transliterate(description.to_s).downcase
      text = text.gsub(%r{\b\d{1,2}[/.-]\d{1,2}([/.-]\d{2,4})?\b}, " ")
      text = text.gsub(/\b\d{3,}\b/, " ")
      text = text.gsub(/[^a-z0-9\s]/, " ")
      words = text.split.reject { |word| word.match?(/\A\d+\z/) || STOPWORDS.include?(word) }
      words.join(" ").squeeze(" ").strip
    end

    # Upper median: for an even number of values it takes the higher middle.
    def median(values)
      sorted = values.sort
      sorted[sorted.size / 2]
    end
  end
end
