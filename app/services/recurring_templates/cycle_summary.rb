# frozen_string_literal: true

# RecurringTemplates::CycleSummary
# Aggregates recurring templates of one kind for a listing period: monthly
# total, pending amount, money already recorded, completion and the next
# pending occurrence.
#
# Periods come in the shapes used by the recurring listings: a PayCycle::Cycle
# when the user configured paydays, or the legacy "YYYY-MM" calendar month.
# Status and paid amounts always come from RecurringTemplate so partial
# receipts keep the same meaning as in the table.
#
# Example: RecurringTemplates::CycleSummary.new(user:, period:, kind: "income").call[:pending_total]
class RecurringTemplates::CycleSummary
  def self.expected_date(template, period)
    return if template.payment_day.blank?

    range = period_range(period)
    date = Dashboard::CycleSummary.next_occurrence_date(template.payment_day, from: range.first)
    date if date <= range.last
  end

  def self.period_range(period)
    return period.to_range if period.respond_to?(:to_range)

    year, month = period.to_s.split("-").map(&:to_i)
    Date.new(year, month, 1).all_month
  rescue ArgumentError, TypeError
    Date.current.all_month
  end

  def initialize(user:, period:, kind:, include_received_total: true)
    @user = user
    @period = period
    @kind = kind
    @include_received_total = include_received_total
  end

  def call
    active = templates.select(&:active?)
    pending = active.reject { |template| completed?(template) }
    completed = active - pending

    {
      monthly_total: active.sum { |template| template.amount.to_d },
      active_count: active.size,
      pending_count: pending.size,
      pending_total: pending.sum { |template| pending_amount(template) },
      received_total: include_received_total? ? templates.sum { |template| paid_amount(template) } : nil,
      received_count: completed.size,
      expected_count: active.size,
      completion_percentage: completion_percentage(completed.size, active.size),
      next_due: next_due(pending)
    }
  end

  private

  attr_reader :user, :period, :kind

  def include_received_total?
    @include_received_total
  end

  def templates
    @templates ||= user.recurring_templates.where(kind: kind).ordered.to_a
  end

  def completed?(template)
    template.status_for(period) == :completed
  end

  def paid_amount(template)
    @paid_amounts ||= {}
    @paid_amounts[template.id] ||= template.paid_amount_for_period(period).to_d
  end

  def pending_amount(template)
    [ template.amount.to_d - paid_amount(template), 0 ].max
  end

  def completion_percentage(completed, expected)
    return 0 if expected.zero?

    (completed.to_f / expected * 100).round
  end

  def next_due(pending)
    candidate = pending.filter_map do |template|
      date = self.class.expected_date(template, period)
      next unless date

      {
        date: date,
        template: template,
        amount: pending_amount(template)
      }
    end.min_by { |row| [ row[:date], row[:template].description.to_s, row[:template].id ] }

    return if candidate.nil?

    {
      date: candidate[:date],
      description: candidate[:template].description.presence || candidate[:template].category.name,
      amount: candidate[:amount]
    }
  end
end
