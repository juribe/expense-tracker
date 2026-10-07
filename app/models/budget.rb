# frozen_string_literal: true

# Budget
# Monthly spending target for an expense category, computed against the user's
# actual expenses for the selected period via the shared CategorySpend service.
# Periods may be a calendar month (Date) or a financial cycle (Range or
# PayCycle::Cycle); since a financial cycle always spans one month, the
# monthly target applies 1:1 to every cycle.
#
# Associations: belongs_to :user, belongs_to :category
# Methods: spent_for(period), remaining_for(period), percentage_for(period),
#          status_for(period), amount_for(period), near_limit?, over_budget?
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

  def spent_for(period)
    args = range_period?(period) ? { range: period.respond_to?(:to_range) ? period.to_range : period } : { month: period }
    @spent_for ||= {}
    @spent_for[period] ||= CategorySpend.call(user: user, category: category, **args)
  end

  def remaining_for(period)
    amount_for(period) - spent_for(period)
  end

  def percentage_for(period)
    return 0.0 if amount_for(period).to_f <= 0

    (spent_for(period) / amount_for(period)) * 100
  end

  def status_for(period)
    pct = percentage_for(period)
    if pct > 100.0
      :over_budget
    elsif pct >= NEAR_LIMIT_PERCENT
      :near_limit
    else
      :on_track
    end
  end

  # The target the period is measured against: the monthly amount applies
  # 1:1 both to calendar months and to financial cycles.
  def amount_for(period)
    monthly_amount.to_d
  end

  # A financial-cycle period (explicit Range or PayCycle::Cycle) spans dates,
  # while a calendar period is a single Date.
  def range_period?(period)
    period.is_a?(Range) || period.is_a?(PayCycle::Cycle)
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
