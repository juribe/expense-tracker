# frozen_string_literal: true

class RecurringTransaction < ApplicationRecord
  TRANSACTION_TYPES = %w[income expense].freeze
  FREQUENCIES = %w[monthly].freeze

  belongs_to :user
  belongs_to :category
  has_many :occurrences,
           class_name: "RecurringTransactionOccurrence",
           dependent: :destroy

  enum :transaction_type, TRANSACTION_TYPES.index_by(&:itself), validate: true
  enum :frequency, FREQUENCIES.index_by(&:itself), default: :monthly, validate: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_day,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 31 }
  validates :description, length: { maximum: 255 }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :of_type, ->(type) { where(transaction_type: type) }
  scope :ordered, -> { order(:payment_day, :id) }

  # The most recent occurrence that generated a real transaction.
  def last_occurrence
    occurrences.order(:transaction_date, :id).last
  end

  # Whether this recurring transaction already generated a transaction
  # within the given period (e.g. "2026-08").
  def processed_for_period?(period)
    occurrences.exists?(period: period)
  end

  # Status shown in the UI for the current month:
  #   :inactive  - configuration is disabled
  #   :completed - already processed for the period
  #   :pending   - active and awaiting processing
  def status_for(period = Date.current.strftime("%Y-%m"))
    return :inactive unless active?
    return :completed if processed_for_period?(period)

    :pending
  end

  # Label of the processing action: "Receive" for income, "Pay" for expense.
  def action_label
    income? ? "Receive" : "Pay"
  end

  def past_action_label
    income? ? "Last received" : "Last paid"
  end
end
