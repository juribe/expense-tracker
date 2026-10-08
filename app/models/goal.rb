# frozen_string_literal: true

# Goal
# A savings goal: a named amount the user wants to accumulate
# ("Fondo de emergencia", "Viaje familiar"). The Pocket (a MoneySource of
# kind "pocket") is the source of truth for how much has been saved —
# saved_amount is never stored or manually editable, it is the pocket's
# balance. Health (on track / at risk / behind) is derived, never persisted.
#
# Associations: belongs_to :user, :pocket (MoneySource kind "pocket")
# Methods: saved_amount, remaining_amount, progress_percentage, completed?,
#   months_remaining, required_monthly_contribution, health
#
# Example: goal = Goal.new(user:, pocket:, name:, target_amount:)
#          goal.required_monthly_contribution # => BigDecimal
class Goal < ApplicationRecord
  PRIORITIES = { low: 0, medium: 1, high: 2 }.freeze
  CATEGORIES = %w[travel savings emergency health education vehicle home
                  holidays gifts taxes other].freeze
  STATUSES = %w[active archived].freeze

  belongs_to :user
  belongs_to :pocket, class_name: "MoneySource"
  # Deleting a goal releases its allocations: the reserved money simply
  # returns to the pocket's unallocated pool.
  has_many :goal_allocations, foreign_key: :financial_goal_id, dependent: :destroy

  validates :name, presence: true
  validates :target_amount, presence: true, numericality: { greater_than: 0 }
  validates :priority, inclusion: { in: PRIORITIES.values }, numericality: { only_integer: true }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validate :pocket_is_pocket_kind
  validate :pocket_belongs_to_user
  validate :pocket_cannot_change_with_allocations, on: :update

  before_validation :normalize_target_amount
  before_validation :normalize_status

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :active, -> { where(status: "active") }

  # The goal's allocations are the single source of truth. A pocket can host
  # several goals; each one only owns what was explicitly assigned to it.
  # A nil pocket (legacy data) reads as zero. When the association is eager
  # loaded the sum is computed in memory (keeps list renders query-free).
  def saved_amount
    return 0.to_d unless pocket

    if goal_allocations.loaded?
      goal_allocations.sum(&:amount).to_d
    else
      goal_allocations.sum(:amount).to_d
    end
  end

  def remaining_amount
    [ target_amount - saved_amount, 0 ].max
  end

  def progress_percentage
    return 0.0 if target_amount.to_f <= 0

    [ (saved_amount / target_amount) * 100, 100.0 ].min
  end

  def completed?
    saved_amount >= target_amount
  end

  # Whole months left to reach the target date; 0 when the date passed or
  # there is no date at all.
  def months_remaining
    return nil if target_date.nil?

    [ ((target_date - Date.current) / 30.44).round, 0 ].max
  end

  # remaining_amount / months_remaining. Nil without a target date, zero
  # once the goal is completed.
  def required_monthly_contribution
    return nil if target_date.nil?
    return 0.to_d if completed?

    remaining_amount / [ months_remaining, 1 ].max
  end

  # Derived goal health, never persisted:
  #   :completed — pocket balance reached the target
  #   :on_track  — progress meets the expected pace (>= 90% of it), or the
  #                goal has no target date (nothing to compare against)
  #   :at_risk   — progress is falling behind (60–90% of expected pace)
  #   :behind    — far behind pace (< 60%) or the target date already passed
  def health
    return :completed if completed?
    return :on_track if target_date.nil?

    total_months = [ ((target_date - created_at.to_date) / 30.44).round, 0 ].max
    elapsed_months = [ ((Date.current - created_at.to_date) / 30.44).round, total_months ].min
    return :behind if total_months.zero?
    return :on_track if elapsed_months.zero?

    expected_fraction = elapsed_months.to_d / total_months
    ratio = (saved_amount / target_amount) / expected_fraction
    return :behind if ratio < 0.6
    return :at_risk if ratio < 0.9

    :on_track
  end

  def archived?
    status == "archived"
  end

  private

  def pocket_is_pocket_kind
    return if pocket.nil?

    errors.add(:pocket, :not_a_pocket) unless pocket.pocket?
  end

  def pocket_belongs_to_user
    return if pocket.nil?

    errors.add(:pocket, :other_user) if pocket.user_id != user_id
  end

  # Moving a goal to another pocket would strand its reservations inside the
  # original pocket. The user must release them first (or delete the goal).
  def pocket_cannot_change_with_allocations
    return if pocket_id_was.nil? || pocket_id == pocket_id_was

    if GoalAllocation.exists?(financial_goal_id: id)
      errors.add(:pocket, :pocket_locked_by_allocations)
    end
  end

  def normalize_target_amount
    self.target_amount = MoneyFormat.normalize(target_amount_before_type_cast || target_amount)
  end

  def normalize_status
    self.status = "active" if status.blank?
  end
end
