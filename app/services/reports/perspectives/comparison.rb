# frozen_string_literal: true

# Reports::Perspectives::Comparison
# Period-over-period reading built on the metrics pass: overall variation,
# direction and the categories with the largest real increases or reductions.
# A category change is significant by monetary impact, not only by percentage,
# so a tiny category with a huge percentage never outranks a meaningful one.
#
# Methods: call
#
# Example: Reports::Perspectives::Comparison.new(metrics: metrics).call[:top_growth]
class Reports::Perspectives::Comparison
  def initialize(metrics:)
    @metrics = metrics
  end

  attr_reader :metrics

  def call
    expenses = metrics[:expenses]
    delta = expenses[:delta].to_d

    {
      available: expenses[:previous].to_d.positive?,
      current: expenses[:total].to_d,
      previous: expenses[:previous].to_d,
      delta: delta,
      delta_pct: expenses[:delta_pct],
      direction: direction(delta),
      partial: metrics[:partial],
      current_count: expenses[:count].to_i,
      previous_count: expenses[:previous_count].to_i,
      top_growth: top_growth,
      top_reduction: top_reduction
    }
  end

  private

  def direction(delta)
    return :increase if delta.positive?
    return :decrease if delta.negative?

    :stable
  end

  def top_growth
    return [] unless available?

    metrics[:categories]
      .select { |row| significant_growth?(row) }
      .sort_by { |row| -row[:delta].to_d }
      .first(2)
  end

  def top_reduction
    return [] unless available?

    metrics[:categories]
      .select { |row| significant_reduction?(row) }
      .sort_by { |row| row[:delta].to_d }
      .first(2)
  end

  def available?
    metrics[:expenses][:previous].to_d.positive?
  end

  def significant_growth?(row)
    delta = row[:delta].to_d
    return false unless delta >= Reports::Perspectives::Thresholds::CATEGORY_CHANGE_MIN_AMOUNT

    row[:delta_pct].nil? ||
      row[:delta_pct] >= Reports::Perspectives::Thresholds::CATEGORY_CHANGE_PCT ||
      delta >= Reports::Perspectives::Thresholds::CATEGORY_CHANGE_ABSOLUTE_OVERRIDE
  end

  def significant_reduction?(row)
    delta = row[:delta].to_d
    return false unless delta <= -Reports::Perspectives::Thresholds::CATEGORY_CHANGE_MIN_AMOUNT

    row[:delta_pct].nil? ||
      row[:delta_pct] <= -Reports::Perspectives::Thresholds::CATEGORY_CHANGE_PCT ||
      delta.abs >= Reports::Perspectives::Thresholds::CATEGORY_CHANGE_ABSOLUTE_OVERRIDE
  end
end
