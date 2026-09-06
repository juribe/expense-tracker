# frozen_string_literal: true

# Budget
# Monthly spending target for an expense category, computed against the user's
# actual expenses for the selected month via the shared CategorySpend service.
#
# Associations: belongs_to :user, belongs_to :category
# Methods: spent_for(month), remaining_for(month), percentage_for(month),
#          status_for(month), near_limit?, over_budget?
#
# Example: Budget.find(id).status_for(Time.zone.today) # => :near_limit
class Budget < ApplicationRecord
  NEAR_LIMIT_PERCENT = 80
  PERIODS = %w[monthly].freeze

  belongs_to :user
  belongs_to :category

  validates :monthly_amount, presence: true, numericality: { greater_than: 0 }
  validates :period, inclusion: { in: PERIODS }
  validates :category_id, presence: true, uniqueness: { scope: :user_id }
  validate :category_must_be_expense_type
  validate :category_must_be_available_to_user

  before_validation :normalize_monthly_amount

  scope :active, -> { where(active: true) }
  scope :for_user, ->(user) { where(user_id: user.id) }

  def spent_for(month)
    @spent_for ||= {}
    @spent_for[month] ||= CategorySpend.call(user: user, category: category, month: month)
  end

  def remaining_for(month)
    monthly_amount.to_d - spent_for(month)
  end

  def percentage_for(month)
    return 0.0 if monthly_amount.to_f <= 0

    (spent_for(month) / monthly_amount.to_d) * 100
  end

  def status_for(month)
    pct = percentage_for(month)
    if pct > 100.0
      :over_budget
    elsif pct >= NEAR_LIMIT_PERCENT
      :near_limit
    else
      :on_track
    end
  end

  def over_budget?(month)
    percentage_for(month) > 100.0
  end

  def near_limit?(month)
    pct = percentage_for(month)
    pct >= NEAR_LIMIT_PERCENT && pct <= 100.0
  end

  def on_track?(month)
    !near_limit?(month) && !over_budget?(month)
  end

  private

  def normalize_monthly_amount
    raw = (monthly_amount_before_type_cast || monthly_amount).to_s.strip
    return if raw.blank?

    if raw.include?(",")
      self.monthly_amount = raw.delete(".").gsub(",", ".")
    elsif raw.scan(".").size > 1
      self.monthly_amount = raw.delete(".")
    end
  end

  def category_must_be_expense_type
    errors.add(:category_id, I18n.t("budgets.validation.expense_type")) if category && category.category_type != "expense"
  end

  def category_must_be_available_to_user
    return if category.nil? || category.is_default? || category.user_id == user_id

    errors.add(:category_id, I18n.t("budgets.validation.invalid_category"))
  end
end
