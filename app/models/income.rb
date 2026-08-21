# frozen_string_literal: true

class Income < ApplicationRecord
  belongs_to :user
  belongs_to :category

  # Scopes
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :in_month, ->(date) { where(date: date.beginning_of_month..date.end_of_month) }
  scope :recent, ->(limit = 5) { order(date: :desc).limit(limit) }

  # Dashboard summary for the given month
  def self.dashboard_summary(user:, month: Time.zone.today)
    incomes = for_user(user).in_month(month)
    total_amount = incomes.sum(:amount)
    by_category = incomes.joins(:category).group("categories.name").sum(:amount)
    recent_incomes = incomes.recent(5)

    {
      total_amount: total_amount,
      by_category: by_category,
      recent_incomes: recent_incomes
    }
  end
end
