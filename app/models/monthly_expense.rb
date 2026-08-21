# frozen_string_literal: true

# A recurring monthly expense configuration. Distinct from regular one-time
# Expense records: paying a MonthlyExpense generates a regular Expense for
# the selected month while the configuration stays active.
class MonthlyExpense < ApplicationRecord
  belongs_to :user
  belongs_to :category

  has_many :monthly_expense_payments, dependent: :destroy
  has_many :expenses, through: :monthly_expense_payments

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_day, numericality: { only_integer: true, greater_than_or_equal_to: 1,
                                          less_than_or_equal_to: 31 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :ordered, -> { order(:payment_day, :id) }

  # The most recent payment made against this configuration, if any.
  def last_payment
    monthly_expense_payments.order(payment_date: :desc).first
  end

  # True when a payment exists whose date falls within +date+'s month.
  def paid_in_month?(date)
    monthly_expense_payments.exists?(
      monthly_expense_payments.arel_table[:payment_date].gteq(date.beginning_of_month)
        .and(monthly_expense_payments.arel_table[:payment_date].lteq(date.end_of_month))
    )
  end

  # Status of the configuration for the current month.
  #
  # @return [Symbol] :paid or :pending
  def status_for(date = Date.current)
    paid_in_month?(date) ? :paid : :pending
  end

  # Creates the regular Expense for the given payment date and records the
  # link between this configuration and the generated Expense. Both writes
  # happen inside a transaction and duplicate payments for the same month
  # are rejected.
  #
  # @param payment_date [Date] date used for the generated Expense
  # @param amount_override [BigDecimal, nil] optional amount override
  # @return [Expense] the generated regular Expense
  # @raise [PaymentError] when inactive, already paid that month, or invalid
  def pay!(payment_date: Date.current, amount_override: nil)
    raise PaymentError, "This monthly expense is inactive." unless active?
    raise PaymentError, "Already paid for #{payment_date.strftime('%B %Y')}." if paid_in_month?(payment_date)

    transaction do
      expense = user.expenses.create!(
        category: category,
        amount: amount_override.presence || amount,
        description: description,
        date: payment_date,
        frequency: "one_time"
      )

      monthly_expense_payments.create!(expense: expense, payment_date: payment_date)

      expense
    end
  rescue ActiveRecord::RecordInvalid => e
    raise PaymentError, e.record.errors.full_messages.to_sentence
  end

  # Domain error raised when a payment cannot be performed.
  class PaymentError < StandardError; end
end
