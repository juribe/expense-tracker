# frozen_string_literal: true

# Reports::Period
# Turns a UI period preset into a date range plus its previous equivalent,
# the shared anchor for every report and its period-over-period comparisons.
#
# With a configured pay schedule the month presets resolve to their pay-cycle
# equivalents (this_month → this_cycle): a cycle opens on payday and runs to
# the day before the next payday, so expenses paid right after payday belong
# to the cycle that funded them. Without a schedule both stay calendar months.
#
# Methods: range, previous_range, bucket, label, preset
#
# Example: Reports::Period.new(preset: "last_3_months", date: Date.current).range
class Reports::Period
  MONTH_PRESETS = %w[this_month last_month last_3_months last_6_months last_12_months this_year custom].freeze
  CYCLE_PRESETS = %w[this_cycle last_cycle last_3_cycles last_6_cycles last_12_cycles this_year custom].freeze
  PRESETS = MONTH_PRESETS

  MONTH_TO_CYCLE = {
    "this_month" => "this_cycle",
    "last_month" => "last_cycle",
    "last_3_months" => "last_3_cycles",
    "last_6_months" => "last_6_cycles",
    "last_12_months" => "last_12_cycles"
  }.freeze

  # Trend granularity switches by span: a couple of months plots daily,
  # half a year weekly, longer horizons monthly.
  DAY_BUCKET_LIMIT = 62
  WEEK_BUCKET_LIMIT = 186

  attr_reader :preset

  def initialize(preset: "this_month", date: Date.current, start_date: nil, end_date: nil, user: nil)
    @date = date
    @start_date = start_date
    @end_date = end_date
    @user = user
    @preset = resolve_preset(preset)
  end

  # Cycle presets stay available for callers that already know the user has a
  # configured cycle, even when this instance was built without one.
  def self.cycles_enabled?(user)
    user.present? && user.financial_cycles_enabled?
  end

  # Whether the resolved preset groups by pay cycles rather than calendar
  # months; report services branch their scaling logic on it.
  def cycle_aligned?
    MONTH_TO_CYCLE.value?(preset)
  end

  # Number of cycles the preset's range covers (1 for this_cycle/last_cycle,
  # N for last_N_cycles); report services scale monthly targets with it.
  def cycles_displayed
    display_count == 2 ? 1 : display_count
  end

  def range
    case preset
    when "this_cycle" then displayed_chain.last.to_range
    when "last_cycle" then displayed_chain.first.to_range
    when "last_3_cycles" then cycle_span
    when "last_6_cycles" then cycle_span
    when "last_12_cycles" then cycle_span
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
  # Cycle presets compare against the same number of whole cycles before.
  def previous_range
    return cycle_previous_range if MONTH_TO_CYCLE.value?(preset)

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
    when "this_cycle" then displayed_chain.last.label
    when "last_cycle" then displayed_chain.first.label
    when "last_3_cycles", "last_6_cycles", "last_12_cycles"
      "#{I18n.l(range.begin)} – #{I18n.l(range.end)}"
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
    return MONTH_TO_CYCLE.fetch(preset) if cycles_enabled? && MONTH_TO_CYCLE.key?(preset)
    return MONTH_TO_CYCLE.key(preset) if MONTH_TO_CYCLE.value?(preset) # cycle preset without schedule

    PRESETS.include?(preset) ? preset : "this_month"
  end

  def cycles_enabled?
    self.class.cycles_enabled?(@user)
  end

  def cycle_chain(count)
    PayCycle.back(@user, count, anchor: @date)
  end

  # The chain of cycles backing the preset: for this_cycle it is the current
  # one; for last_cycle the previous one plus the current (the current only
  # anchors where "previous" ends); for last_N_cycles the N ending today.
  def displayed_chain
    @displayed_chain ||= cycle_chain(display_count)
  end

  def cycle_span
    chain = displayed_chain
    chain.first.starts..chain.last.ends
  end

  def cycle_previous_range
    preceding = PayCycle.back(@user, cycle_count, anchor: displayed_chain.first.starts - 1.day)
    preceding.first.starts..preceding.last.ends
  end

  def cycle_count
    preset == "last_cycle" ? 1 : display_count
  end

  def display_count
    case preset
    when "this_cycle" then 1
    when "last_cycle" then 2
    else preset[/^last_(\d+)_cycles$/, 1].to_i
    end
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
