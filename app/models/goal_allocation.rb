# frozen_string_literal: true

# GoalAllocation
# An internal reservation: how much of a Pocket's balance is assigned to a
# Financial Goal. It never moves money — the amount stays inside the pocket;
# only its purpose changes. Positive amounts assign money to the goal,
# negative amounts release it (back to the pocket's unallocated pool, or as
# the compensating half of a reallocation between goals). The allocation
# records the pocket explicitly for audit, but it must always match the
# goal's pocket.
#
# Associations: belongs_to :financial_goal (Goal), :pocket (MoneySource)
#
# Example: goal_allocations.create!(financial_goal: goal, pocket: goal.pocket,
#   amount: 500_000, date: Date.current)
class GoalAllocation < ApplicationRecord
  belongs_to :financial_goal, class_name: "Goal"
  belongs_to :pocket, class_name: "MoneySource"

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true
  validate :pocket_matches_goal
  validate :goal_saved_cannot_go_negative
  validate :pocket_unallocated_cannot_go_negative

  before_validation :normalize_amount
  before_validation :inherit_pocket_from_goal

  private

  # The allocation always records the goal's pocket; callers only need to
  # supply goal + amount.
  def inherit_pocket_from_goal
    self.pocket_id ||= financial_goal&.pocket_id
  end

  # The pocket on the allocation is an audit copy of the goal's pocket: the
  # money is reserved inside that pocket, so both must always agree.
  def pocket_matches_goal
    return if financial_goal.nil? || pocket.nil?

    unless pocket_id == financial_goal.pocket_id
      errors.add(:pocket, :pocket_mismatch)
    end
  end

  # A release cannot sink the goal below zero.
  def goal_saved_cannot_go_negative
    return if financial_goal.nil? || amount.nil?

    current = financial_goal.goal_allocations.where.not(id: id).sum(:amount).to_d
    if (current + amount.to_d).negative?
      errors.add(:amount, :goal_saved_negative)
    end
  end

  # No write can push the pocket's total allocations above its real balance.
  def pocket_unallocated_cannot_go_negative
    return if pocket.nil? || amount.nil?

    other_allocations = GoalAllocation.where(pocket_id: pocket_id).where.not(id: id).sum(:amount).to_d
    if other_allocations + amount.to_d > pocket.balance
      errors.add(:amount, :pocket_overallocated)
    end
  end

  def normalize_amount
    self.amount = MoneyFormat.normalize(amount_before_type_cast || amount) if amount.present?
  end
end
