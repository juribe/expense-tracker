# frozen_string_literal: true

# Payment
# Application of an existing Expense to a debt (credit card or loan); not a
# new cash movement. Balance effects move only principal, never the totals.
#
# Associations: belongs_to :expense (Transaction), :money_source (debt target)
# Methods: distribution_total
#
# Example: Payment.create!(expense: expense, money_source: mortgage, amount: 1_500_000,
#   principal_amount: 900_000, interest_amount: 400_000, insurance_amount: 150_000)
class Payment < ApplicationRecord
  COMPONENTS = %i[principal_amount interest_amount insurance_amount other_amount].freeze

  scope :for_user, ->(user) { where(user_id: user.id) }

  belongs_to :user
  belongs_to :expense, class_name: "Transaction"
  belongs_to :money_source

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :principal_amount, :interest_amount, :insurance_amount, :other_amount,
            numericality: { greater_than_or_equal_to: 0 }
  validates :source, presence: true

  validate :expense_belongs_to_user
  validate :target_belongs_to_user
  validate :target_is_debt
  validate :amount_matches_expense
  validate :components_sum_to_amount

  # The payment's date is the expense's effective date — a distribution is not
  # an independent movement, so it never carries its own timeline.
  after_initialize :carry_date_and_source_from_expense

  # Balance movement happens after commit, same convention as the transaction
  # BalanceSync callbacks.
  after_commit on: :create do
    Payments::BalanceEffect.play!(self)
  end

  after_commit on: :update, if: :saved_change_to_principal_amount? do
    Payments::BalanceEffect.play!(self, previous_principal: principal_amount_before_last_save)
  end

  before_destroy :remember_previous_principal

  after_commit on: :destroy do
    Payments::BalanceEffect.play!(self, previous_principal: @previous_principal)
  end

  def distribution_total
    COMPONENTS.sum { |component| self[component].to_d }
  end

  def expense_money_source_id
    expense&.money_source_id
  end

  private

  def expense_belongs_to_user
    return if user_id.nil? || expense.nil?

    errors.add(:expense, :other_user) if expense.user_id != user_id
  end

  def target_belongs_to_user
    return if user_id.nil? || money_source.nil?

    errors.add(:money_source, :other_user) if money_source.user_id != user_id
  end

  def target_is_debt
    return if money_source.nil?

    errors.add(:money_source, :not_debt) unless money_source.debt_payment_target?
  end

  def amount_matches_expense
    return if amount.nil? || expense.nil?

    errors.add(:amount, :must_match_expense) if amount.to_d != expense.amount.to_d.abs
  end

  def components_sum_to_amount
    return if amount.nil? || COMPONENTS.any? { |component| self[component].nil? }

    errors.add(:base, :distribution_mismatch) if distribution_total != amount.to_d
  end

  def carry_date_and_source_from_expense
    return if expense.nil?

    self.date = expense.date if date.blank?
    self.source ||= "manual"
  end

  def remember_previous_principal
    @previous_principal = principal_amount.to_d
  end
end
