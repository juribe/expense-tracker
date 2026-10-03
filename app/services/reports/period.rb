# frozen_string_literal: true

# Reports::Period
# Turns a UI period preset into a date range plus its previous equivalent,
# the shared anchor for every report and its period-over-period comparisons.
#
# Methods: range, previous_range, bucket, label, preset
#
# Example: Reports::Period.new(preset: "last_3_months", date: Date.current).range
class Reports::Period
  PRESETS = %w[this_month last_month last_3_months last_6_months last_12_months this_year custom].freeze

  # Trend granularity switches by span: a couple of months plots daily,
  # half a year weekly, longer horizons monthly.
  DAY_BUCKET_LIMIT = 62
  WEEK_BUCKET_LIMIT = 186

  attr_reader :preset

  def initialize(preset: "this_month", date: Date.current, start_date: nil, end_date: nil)
    @date = date
    @start_date = start_date
    @end_date = end_date
    @preset = resolve_preset(preset)
  end

  def range
    case preset
    when "this_month" then month_range(@date)
    when "last_month" then month_range(@date.prev_month)
    when "last_3_months" then months_back_range(3)
    when "last_6_months" then months_back_range(6)
    when "last_12_months" then months_back_range(12)
    when "this_year" then @date.beginning_of_year..@date.end_of_year
    else custom_range
    end
  end

  # Calendar-aligned presets compare against the same number of whole months
  # before the range (September vs August, Q3 vs Q2). Arbitrary custom windows
  # compare against the immediately preceding window of equal day-length.
  def previous_range
    begin_month = range.begin - span_months.months
    end_month = range.begin - 1.month
    return month_range(begin_month).begin..month_range(end_month).end if month_aligned?

    length = (range.end - range.begin + 1).to_i
    (range.begin - length.days)..(range.begin - 1.day)
  end

  def bucket
    span = (range.end - range.begin + 1).to_i
    return :day if span <= DAY_BUCKET_LIMIT
    return :week if span <= WEEK_BUCKET_LIMIT

    :month
  end

  def label
    case preset
    when "this_month" then l_month(@date)
    when "last_month" then l_month(@date.prev_month)
    when "last_3_months", "last_6_months", "last_12_months"
      "#{I18n.l(range.begin, format: '%b')}–#{I18n.l(range.end, format: '%b %Y')}"
    else
      "#{I18n.l(range.begin)} – #{I18n.l(range.end)}"
    end
  end

  private

  def resolve_preset(raw)
    preset = raw.to_s
    return "custom" if preset == "custom" && @start_date.present? && @end_date.present?

    PRESETS.include?(preset) ? preset : "this_month"
  end

  def month_range(date)
    date.beginning_of_month..date.end_of_month
  end

  def months_back_range(count)
    month_range(@date.beginning_of_month - (count - 1).months).begin..month_range(@date).end
  end

  def custom_range
    return month_range(@date) if @start_date.blank? || @end_date.blank?

    @start_date..@end_date
  end

  def month_aligned?
    range.begin == range.begin.beginning_of_month && range.end == range.end.end_of_month
  end

  def span_months
    end_month = range.end.year * 12 + range.end.month
    begin_month = range.begin.year * 12 + range.begin.month
    end_month - begin_month + 1
  end

  def l_month(date)
    I18n.l(date, format: "%b %Y")
  end
end
