# frozen_string_literal: true

class Expense < Transaction
  default_scope { expense }

  scope :in_category, ->(category_id) { where(category_id: category_id) }

  # Helper for the dashboard
  def self.dashboard_summary(user:, month: Time.zone.today)
    expenses = for_user(user).in_month(month)
    total_amount = expenses.sum(:amount)
    by_category = expenses.joins(:category).group("categories.name").sum(Arel.sql("ABS(amount)"))
    recent_expenses = expenses.recent(5)
    {
      total_amount: total_amount,
      by_category: by_category,
      recent_expenses: recent_expenses
    }
  end
end
