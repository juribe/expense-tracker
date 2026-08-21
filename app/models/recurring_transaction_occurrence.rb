# frozen_string_literal: true

class RecurringTransactionOccurrence < ApplicationRecord
  belongs_to :recurring_transaction

  # Polymorphic link to the generated Income/Expense. The association is named
  # +generated_transaction+ because Active Record already defines a +transaction+
  # method on every model; the DB columns remain transaction_type/transaction_id.
  belongs_to :generated_transaction,
             polymorphic: true,
             foreign_key: :transaction_id,
             foreign_type: :transaction_type

  validates :transaction_date, presence: true
  validates :period, presence: true, format: { with: /\A\d{4}-\d{2}\z/, message: "must be in YYYY-MM format" }

  # Hard guarantee against duplicate monthly processing (backed by a unique index).
  validates :period, uniqueness: { scope: :recurring_transaction_id }
end
