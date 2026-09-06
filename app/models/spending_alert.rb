# frozen_string_literal: true

# SpendingAlert
# A single, deduplicated spending notification for one (user, category, month).
#
# Kinds: budget_threshold (>=80% of budget), budget_exceeded (>=100%),
#   spending_increase (>=35% vs previous month).
# Associations: belongs_to :user, belongs_to :category.
# Scopes: unread, budget, spending, for_month, for_current_month.
#
# Example: current_user.spending_alerts.unread.for_current_month
class SpendingAlert < ApplicationRecord
  KINDS = %w[budget_threshold budget_exceeded spending_increase].freeze

  belongs_to :user
  belongs_to :category

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :month, presence: true
  validates :pct, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :budget, -> { where(kind: %w[budget_threshold budget_exceeded]) }
  scope :spending, -> { where(kind: "spending_increase") }
  scope :for_month, ->(month) { where(month: month.strftime("%Y-%m")) }
  scope :for_current_month, -> { for_month(Time.zone.today) }

  def budget?
    %w[budget_threshold budget_exceeded].include?(kind)
  end

  def budget_amount
    return nil unless budget?

    user.budgets.find_by(category_id: category_id)&.monthly_amount
  end

  def read?
    read_at.present?
  end

  def unread?
    read_at.blank?
  end
end