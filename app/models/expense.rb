# frozen_string_literal: true

class Expense < ApplicationRecord
  belongs_to :user
  belongs_to :category

  # Scopes
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :in_month, ->(date) { where(created_at: date.beginning_of_month..date.end_of_month) }
  scope :recent, ->(limit = 5) { order(created_at: :desc).limit(limit) }
  scope :by_category, -> { group(:category_id).sum(:amount) }

  # Helper for the dashboard
  def self.dashboard_summary(user:, month: Time.zone.today)
    expenses = for_user(user).in_month(month)
    total_amount = expenses.sum(:amount)
    by_category = expenses.joins(:category).group('categories.name').sum(:amount)
    recent_expenses = expenses.recent(5)
    {
      total_amount: total_amount,
      by_category: by_category,
      recent_expenses: recent_expenses
    }
  end
end
