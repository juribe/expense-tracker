# frozen_string_literal: true

# Goal
# A savings goal: a named amount the user wants to accumulate
# ("Fondo de emergencia", "Viaje familiar"). Progress is tracked with
# saved_amount against target_amount; target_date is optional.
#
# Associations: belongs_to :user
# Methods: progress_percentage, remaining_amount, completed?
#
# Example: Goal.new(user:, name:, target_amount:).progress_percentage # => 40.0
class Goal < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :target_amount, presence: true, numericality: { greater_than: 0 }
  validates :saved_amount, numericality: { greater_than_or_equal_to: 0 }

  before_validation :normalize_amounts

  scope :for_user, ->(user) { where(user_id: user.id) }

  def progress_percentage
    return 0.0 if target_amount.to_f <= 0

    [ (saved_amount / target_amount) * 100, 100.0 ].min
  end

  def remaining_amount
    [ target_amount - saved_amount, 0 ].max
  end

  def completed?
    saved_amount >= target_amount
  end

  private

  def normalize_amounts
    self.target_amount = MoneyFormat.normalize(target_amount_before_type_cast || target_amount)
    self.saved_amount = MoneyFormat.normalize(saved_amount_before_type_cast || saved_amount)
  end
end
