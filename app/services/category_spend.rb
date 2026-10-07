# frozen_string_literal: true

# CategorySpend
# Single source of truth for how much a user spent in one category during a
# period. Shared by the budget cards and the alert engine so refunds and
# income follow identical semantics everywhere.
#
# `month:` sums the calendar month of the given date; `range:` sums any
# explicit range, which is how pay-cycle callers (PayCycle) express a cycle.
#
# Example: CategorySpend.call(user: user, category: category, month: Time.zone.today)
#          CategorySpend.call(user: user, category: category, range: cycle_range)
class CategorySpend
  def self.call(user:, category:, month: nil, range: nil)
    Expense.for_user(user).where(date: span(month, range))
           .in_category(category.id).sum(:amount).abs
  end

  def self.span(month, range)
    return range if range.present?

    month.beginning_of_month..month.end_of_month
  end
end