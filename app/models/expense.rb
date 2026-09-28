# frozen_string_literal: true

class Expense < Transaction
  default_scope { expense }

  # Counter cache on categories.expenses_count: the categories index (app
  # root) renders the count per category without per-row COUNT queries.
  belongs_to :category, counter_cache: true, optional: true

  scope :in_category, ->(category_id) { where(category_id: category_id) }

  # Helper for the dashboard
  def self.dashboard_summary(user:, month: Time.zone.today)
    expenses = for_user(user).in_month(month)
    total_amount = expenses.sum(:amount)
    by_category = expenses.joins(:category).group("categories.name").sum(Arel.sql("ABS(amount)"))
    recent_expenses = expenses.recent(5).includes(:category)
    {
      total_amount: total_amount,
      by_category: by_category,
      recent_expenses: recent_expenses
    }
  end
end
