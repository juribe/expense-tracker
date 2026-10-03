# frozen_string_literal: true

# Reports::Recurring
# Recurring payments report: templates with monthly/annual equivalents,
# committed amounts and upcoming payments within the next seven days.
# Amounts come from the template's recorded data; unknown frequencies are
# never extrapolated beyond a monthly fallback factor.
#
# Methods: call
#
# Example: Reports::Recurring.new(user: user, filter: filter).call[:monthly_committed]
class Reports::Recurring < Reports::Base
  UPCOMING_DAYS = 7

  # Rational factors keep the conversion exact (300_000/3 is exactly 100_000).
  # Anything unknown counts once a month, matching how the app records
  # frequencies today.
  MONTHLY_FACTORS = {
    "weekly" => Rational(52, 12), "biweekly" => Rational(26, 12), "monthly" => Rational(1),
    "quarterly" => Rational(1, 3), "annual" => Rational(1, 12),
    "yearly" => Rational(1, 12), "daily" => Rational(30)
  }.freeze

  def call
    items = template_items
    active = items.select { |item| item[:active] }
    {
      period: period,
      items: items,
      monthly_committed: active.sum { |item| item[:monthly_equivalent] },
      annual_committed: active.sum { |item| item[:monthly_equivalent] * 12 },
      upcoming: upcoming(active)
    }
  end

  private

  def template_items
    RecurringTemplate.for_user(user)
                     .includes(:category, :money_source)
                     .ordered
                     .map { |template| item(template) }
  end

  def item(template)
    monthly = (template.amount.to_r * factor(template.frequency)).to_d
    {
      id: template.id, description: template.description, kind: template.kind.to_sym,
      amount: template.amount, frequency: template.frequency,
      monthly_equivalent: monthly,
      annual_equivalent: monthly * 12,
      category_name: template.category.name, money_source_name: template.money_source&.name,
      active: template.active?, payment_day: template.payment_day
    }
  end

  def factor(frequency)
    MONTHLY_FACTORS.fetch(frequency.to_s, 1.to_d)
  end

  def upcoming(items)
    items.map { |item| item.merge(next_due_date: next_due_date(item[:payment_day])) }
         .select { |item| item[:next_due_date] && item[:next_due_date] <= Date.current + UPCOMING_DAYS }
         .sort_by { |item| item[:next_due_date] }
  end

  def next_due_date(day)
    return nil if day.blank?

    candidate = Date.new(Date.current.year, Date.current.month, day.to_i)
    candidate = candidate.next_month if candidate < Date.current
    candidate
  rescue ArgumentError, TypeError, Date::Error
    # payment day beyond the month's length, e.g. 31 in September
    Date.current.end_of_month
  end
end
