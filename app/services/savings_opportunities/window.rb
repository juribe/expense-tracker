# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::Window
  # Date windows for the savings analysis: the current (partial) period, the
  # last three complete periods and the equivalent elapsed days of each one.
  # Periods follow the user's pay cycle when configured and calendar months
  # otherwise, so comparisons never mix cycles with months.
  #
  # Methods: current_range, complete_ranges, comparable_ranges, series_ranges,
  #          series_labels, recurring_range, elapsed_days, label
  #
  # Example: SavingsOpportunities::Window.new(user: user).comparable_ranges
  class Window
    COMPLETE_PERIODS = 3
    SERIES_PERIODS = 2

    attr_reader :user, :date

    def initialize(user:, date: Date.current)
      @user = user
      @date = date.to_date
    end

    # Current period up to today. Used as-is for "observed spending"; never
    # compared against a whole previous month.
    def current_range
      @current_range ||= current_period.begin..[ @date, current_period.end ].min
    end

    # The last three complete periods, oldest first.
    def complete_ranges
      @complete_ranges ||= previous_periods(COMPLETE_PERIODS)
    end

    # The same elapsed days of each complete period. This is the fair
    # comparison base for a month that is still in progress.
    def comparable_ranges
      @comparable_ranges ||= complete_ranges.map do |range|
        comparable_end = [ range.begin + elapsed_days - 1, range.end ].min
        range.begin..comparable_end
      end
    end

    # Last two complete periods plus the current one: the bars shown per
    # category.
    def series_ranges
      complete_ranges.last(SERIES_PERIODS) + [ current_range ]
    end

    def series_labels
      series_ranges.map { |range| I18n.l(range.begin, format: "%b") }
    end

    # Recurring detection looks far enough back to see at least four monthly
    # payments.
    def recurring_range
      complete_ranges.first.begin..current_range.end
    end

    def elapsed_days
      (current_range.end - current_range.begin).to_i + 1
    end

    def label
      I18n.t("savings_opportunities.window.label", count: COMPLETE_PERIODS,
             default: "Últimos %{count} meses y el período en curso")
    end

    def cycle_aligned?
      Reports::Period.cycles_enabled?(user)
    end

    private

    def current_period
      if cycle_aligned?
        PayCycle.containing(user, date).to_range
      else
        date.beginning_of_month..date.end_of_month
      end
    end

    def previous_periods(count)
      if cycle_aligned?
        PayCycle.back(user, count + 1, anchor: date).first(count).map(&:to_range)
      else
        (count.downto(1)).map do |months_back|
          start = date.beginning_of_month - months_back.months
          start..start.end_of_month
        end
      end
    end
  end
end
