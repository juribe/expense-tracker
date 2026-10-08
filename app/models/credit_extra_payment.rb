# frozen_string_literal: true

# CreditExtraPayment
# A REAL extraordinary payment on a debt. For amortizing loans: a cash
# Expense from a funding money source plus a principal-only Payment applied
# to the debt through the standard store machinery (Payments::BalanceEffect
# moves the loan balance, the payment shows up in the loan's payment list
# and reports). For revolving credit (cards / crédito rotativo,
# application_type "reduce_balance"): a Transfer from a funding source that
# simply lowers the outstanding balance — no Expense, no schedule, no
# installments. Each record keeps an effect snapshot (principal reduction,
# installments affected, balance before/after) for the history view.
#
# Associations: belongs_to :money_source (debt), :funding_money_source,
#               :payment (Transaction), :expense (Transaction), :transfer
# Methods: APPLICATION_TYPES
class CreditExtraPayment < ApplicationRecord
  APPLICATION_TYPES = %w[reduce_term reduce_installment prepay_installments reduce_balance].freeze

  belongs_to :money_source
  belongs_to :funding_money_source, class_name: "MoneySource"
  belongs_to :payment, optional: true, class_name: "Payment"
  belongs_to :expense, optional: true, class_name: "Transaction", foreign_key: :expense_id
  belongs_to :transfer, optional: true

  validates :date, :amount, :application_type, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :application_type, inclusion: { in: APPLICATION_TYPES }
  validates :principal_reduction, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :funding_money_source_id, presence: true

  validate :projection_must_exist
  validate :reduce_balance_targets_revolving_credit
  validate :funding_belongs_to_user
  validate :funding_is_payment_source

  scope :recent_first, -> { order(date: :desc, id: :desc) }

  def discard!
    payment_id = self.payment_id
    expense_id = self.expense_id
    transfer_id = self.transfer_id
    # Nullify the links first: destroying the payment/expense/transfer while
    # this row still references them would violate the foreign keys. The
    # balance callbacks (BalanceEffect, Transaction/Transfer syncs) then
    # revert the real numbers.
    update_columns(payment_id: nil, expense_id: nil, transfer_id: nil)
    Payment.find_by(id: payment_id)&.destroy
    Transaction.find_by(id: expense_id)&.destroy
    # The transfer's callbacks restore the funding account and lower the
    # debt's balance by the same delta it moved.
    Transfer.find_by(id: transfer_id)&.destroy
    destroy!
  end

  private

  # Only amortizing credits carry a projection: reduce_term / reduce_installment
  # / prepay_installments are schedule concepts. A revolving payment simply
  # lowers the balance, so it never needs one.
  def projection_must_exist
    return if application_type == "reduce_balance"
    return if money_source&.credit_projection.present?

    errors.add(:base, :missing_projection)
  end

  # reduce_balance is the revolving flavor (credit card / crédito rotativo);
  # an amortizing loan distinguishes its abonos through the schedule types.
  def reduce_balance_targets_revolving_credit
    return if application_type != "reduce_balance" || money_source.nil?

    return if money_source.credit_card? || money_source.revolving?

    errors.add(:application_type, :invalid)
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
