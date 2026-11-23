# frozen_string_literal: true

# GoalAllocation
# The single ledger for a goal's contributions and withdrawals. A row with a
# pocket reserves part of that pocket's balance for the goal; a row without a
# pocket is a virtual contribution/withdrawal for a simple-mode goal. Positive
# amounts add to the goal, negative amounts release it. The allocation never
# moves money by itself.
#
# Associations: belongs_to :financial_goal (Goal), :pocket (optional)
#
# Example: goal_allocations.create!(financial_goal: goal, pocket: goal.pocket,
#   amount: 500_000, date: Date.current)
class GoalAllocation < ApplicationRecord
  belongs_to :financial_goal, class_name: "Goal"
  belongs_to :pocket, class_name: "MoneySource", optional: true

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true
  validates :idempotency_key, uniqueness: { scope: :financial_goal_id }, allow_nil: true
  validate :pocket_matches_goal
  validate :goal_saved_cannot_go_negative
  validate :pocket_unallocated_cannot_go_negative

  scope :virtual, -> { where(pocket_id: nil) }
  scope :pocket_backed, -> { where.not(pocket_id: nil) }

  def virtual?
    pocket_id.nil?
  end

  def contribution?
    amount.to_d.positive?
  end

  def withdrawal?
    amount.to_d.negative?
  end

  before_validation :normalize_amount
  before_validation :inherit_pocket_from_goal

  private

  # The allocation always records the goal's pocket; callers only need to
  # supply goal + amount.
  def inherit_pocket_from_goal
    self.pocket_id ||= financial_goal&.pocket_id
  end

  # The pocket on the allocation is an audit copy of the goal's pocket: the
  # money is reserved inside that pocket, so both must always agree. A virtual
  # goal cannot carry a pocket-backed allocation.
  def pocket_matches_goal
    return if financial_goal.nil?

    if financial_goal.pocket_id.present?
      errors.add(:pocket, :pocket_mismatch) unless pocket_id == financial_goal.pocket_id
    elsif pocket_id.present?
      errors.add(:pocket, :virtual_goal_has_pocket)
    end
  end

  # A release cannot sink the goal below zero. Only the rows that currently
  # count for the goal participate (virtual or pocket-backed, never both).
  def goal_saved_cannot_go_negative
    return if financial_goal.nil? || amount.nil?

    current = financial_goal.savings_allocations.where.not(id: id).sum(:amount).to_d
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
