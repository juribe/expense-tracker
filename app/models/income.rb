# frozen_string_literal: true

class Income < Transaction
  default_scope { income }

  # Dashboard summary for the given month
  def self.dashboard_summary(user:, month: Time.zone.today)
    incomes = for_user(user).in_month(month)
    total_amount = incomes.sum(:amount)
    by_category = incomes.joins(:category).group("categories.name").sum(:amount)
    recent_incomes = incomes.recent(5)

    {
      total_amount: total_amount,
      signed_total_amount: total_amount,
      by_category: by_category,
      recent_incomes: recent_incomes
    }
  end
end
