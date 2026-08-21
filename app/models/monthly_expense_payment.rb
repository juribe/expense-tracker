# frozen_string_literal: true

# Links a paid regular Expense back to the MonthlyExpense configuration
# that generated it, tracking which month was covered by the payment.
class MonthlyExpensePayment < ApplicationRecord
  belongs_to :monthly_expense
  belongs_to :expense

  validate :one_payment_per_month

  private

  def one_payment_per_month
    scope = monthly_expense&.monthly_expense_payments
    return if scope.nil? || payment_date.blank?

    conflict = scope.where.not(id: id).exists?(
      scope.arel_table[:payment_date].gteq(payment_date.beginning_of_month)
        .and(scope.arel_table[:payment_date].lteq(payment_date.end_of_month))
    )
    errors.add(:payment_date, "already has a payment for this month") if conflict
  end
end
