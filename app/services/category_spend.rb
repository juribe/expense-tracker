# frozen_string_literal: true

# CategorySpend
# Single source of truth for how much a user spent in one category during a
# month. Shared by the budget cards and the alert engine so refunds and income
# follow identical semantics everywhere.
#
# Example: CategorySpend.call(user: user, category: category, month: Time.zone.today)
class CategorySpend
  def self.call(user:, category:, month:)
    Expense.for_user(user).in_month(month).in_category(category.id).sum(:amount).abs
  end
end