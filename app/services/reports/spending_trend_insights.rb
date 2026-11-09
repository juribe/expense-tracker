# frozen_string_literal: true

# Reports::SpendingTrendInsights
# Deterministic readings for the spending-trend report: peak-day concentration,
# weekday/weekend pattern and exceptional daily spending. Conclusions are only
# emitted when the sample is large enough to support them.
#
# Methods: call
#
# Example: Reports::SpendingTrendInsights.new(trend: trend_data).call[:items]
class Reports::SpendingTrendInsights
  MIN_SPENDING_DAYS = 3
  MIN_PATTERN_DAYS = 7
  MIN_WEEKEND_DAYS = 2
  MIN_WEEKDAY_DAYS = 4
  MIN_EXCEPTIONAL_DAYS = 5
  CONCENTRATION_SHARE_PCT = 25.0
  EXCEPTIONAL_MULTIPLE = 3.0
  PATTERN_DIFFERENCE = 1.25

  def initialize(trend:)
    @trend = trend
  end

  def call
    items = [ concentration_item, patterns_item, exceptional_item ]

    {
      items: items,
      insufficient: items.none? { |item| item[:available] }
    }
  end

  private

  attr_reader :trend

  def daily
    @daily ||= trend[:daily_series] || []
  end

  def elapsed_daily
    @elapsed_daily ||= daily.select { |point| point[:date] <= Date.current }
  end

  def total
    @total ||= trend[:total].to_d
  end

  def days_with_expenses
    trend[:days_with_expenses].to_i
  end

  def peak
    @peak ||= daily.select { |point| point[:total].to_d.positive? }.max_by { |point| point[:total] }
  end

  def concentration_item
    item(:concentration) do
      next nil unless enough_spending_days?
      next nil unless peak && total.positive?

      share = peak[:total].to_d / total * 100
      next nil if share < CONCENTRATION_SHARE_PCT

      I18n.t("reports.trend.insights.concentration",
             date: day_label(peak[:date]), pct: percentage(share))
    end
  end

  def patterns_item
    item(:patterns) do
      next nil unless enough_pattern_sample?

      weekend = average_daily(weekend_points)
      weekday = average_daily(weekday_points)
      next nil unless weekend.positive? && weekday.positive?

      ratio = weekend >= weekday ? weekend / weekday : weekday / weekend
      next nil if ratio < PATTERN_DIFFERENCE

      key = weekend > weekday ? :patterns_weekend : :patterns_weekday
      I18n.t("reports.trend.insights.#{key}",
             weekend: MoneyFormat.currency(weekend), weekday: MoneyFormat.currency(weekday))
    end
  end

  def exceptional_item
    item(:exceptional) do
      next nil unless enough_exceptional_sample?

      average = trend[:average_daily].to_d
      next nil unless average.positive? && peak

      multiple = peak[:total].to_d / average
      next nil if multiple < EXCEPTIONAL_MULTIPLE

      I18n.t("reports.trend.insights.exceptional",
             date: day_label(peak[:date]), multiple: decimal(multiple))
    end
  end

  def item(key)
    body = yield

    {
      key: key,
      title: I18n.t("reports.trend.insights.titles.#{key}"),
      body: body.presence || I18n.t("reports.trend.insights.insufficient"),
      available: body.present?
    }
  end

  def enough_spending_days?
    days_with_expenses >= MIN_SPENDING_DAYS && total.positive?
  end

  def enough_pattern_sample?
    elapsed_daily.size >= MIN_PATTERN_DAYS &&
      weekend_points.size >= MIN_WEEKEND_DAYS &&
      weekday_points.size >= MIN_WEEKDAY_DAYS &&
      enough_spending_days?
  end

  def enough_exceptional_sample?
    trend[:elapsed_days].to_i >= MIN_EXCEPTIONAL_DAYS &&
      enough_spending_days?
  end

  def weekend_points
    @weekend_points ||= elapsed_daily.select { |point| point[:date].on_weekend? }
  end

  def weekday_points
    @weekday_points ||= elapsed_daily.reject { |point| point[:date].on_weekend? }
  end

  def average_daily(points)
    return 0.to_d if points.empty?

    points.sum { |point| point[:total].to_d } / points.size
  end

  def day_label(date)
    I18n.l(date, format: "%-d de %B").downcase
  end

  def percentage(value)
    ActionController::Base.helpers.number_to_percentage(value, precision: 0)
  end

  def decimal(value)
    ActionController::Base.helpers.number_with_precision(
      value, precision: 1, strip_insignificant_zeros: true
    )
  end
end
