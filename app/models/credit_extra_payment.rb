# frozen_string_literal: true

# CreditExtraPayment
# A REAL extraordinary payment on a loan: a cash Expense from a funding
# money source plus a principal-only Payment applied to the debt through the
# standard store machinery (Payments::BalanceEffect moves the loan balance,
# the payment shows up in the loan's payment list and reports). Each record
# keeps an effect snapshot (principal reduction, installments affected,
# interest saved) for the history view.
#
# Associations: belongs_to :money_source (debt), :funding_money_source,
#               :payment (Transaction), :expense (Transaction)
# Methods: APPLICATION_TYPES
class CreditExtraPayment < ApplicationRecord
  APPLICATION_TYPES = %w[reduce_term reduce_installment prepay_installments].freeze

  belongs_to :money_source
  belongs_to :funding_money_source, class_name: "MoneySource"
  belongs_to :payment, optional: true, class_name: "Payment"
  belongs_to :expense, optional: true, class_name: "Transaction", foreign_key: :expense_id

  validates :date, :amount, :application_type, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :application_type, inclusion: { in: APPLICATION_TYPES }
  validates :principal_reduction, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :funding_money_source_id, presence: true

  validate :projection_must_exist
  validate :funding_belongs_to_user
  validate :funding_is_payment_source

  scope :recent_first, -> { order(date: :desc, id: :desc) }

  def discard!
    payment_id = self.payment_id
    expense_id = self.expense_id
    # Nullify the links first: destroying the payment/expense while this row
    # still references them would violate the foreign keys. Payments::Balance
    # Effect and the transaction callbacks then revert the real numbers.
    update_columns(payment_id: nil, expense_id: nil)
    Payment.find_by(id: payment_id)&.destroy
    Transaction.find_by(id: expense_id)&.destroy
    destroy!
  end

  private

  def projection_must_exist
    return if money_source&.credit_projection.present?

    errors.add(:base, :missing_projection)
  end

  def funding_belongs_to_user
    return if funding_money_source.nil? || money_source.nil?

    return if funding_money_source.user_id == money_source.user_id

    errors.add(:funding_money_source, :other_user)
  end

  def funding_is_payment_source
    return if funding_money_source&.payment_source?

    errors.add(:funding_money_source, :not_a_payment_source)
  end
end
