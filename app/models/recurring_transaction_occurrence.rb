# frozen_string_literal: true

class RecurringTransactionOccurrence < ApplicationRecord
  belongs_to :recurring_transaction
  belongs_to :transaction, polymorphic: true

  validates :transaction_date, presence: true
  validates :period, presence: true, format: { with: /\A\d{4}-\d{2}\z/, message: "must be in YYYY-MM format" }

  # Hard guarantee against duplicate monthly processing (backed by a unique index).
  validates :period, uniqueness: { scope: :recurring_transaction_id }
end
