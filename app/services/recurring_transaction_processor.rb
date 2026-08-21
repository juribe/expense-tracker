# frozen_string_literal: true

# Turns a recurring configuration into a real one-time transaction.
#
#   RecurringTransactionProcessor.call(
#     recurring_transaction: recurring_transaction,
#     amount: 6500.00,
#     date: Date.new(2026, 8, 18)
#   )
#
# Rules:
# * The recurring transaction must be active.
# * The period is derived from the given date ("YYYY-MM").
# * A recurring transaction can only be processed once per period.
# * Processing creates a normal Income or Expense (frequency: "one_time")
#   plus an occurrence record linking back to it.
# * Everything runs inside a single database transaction.
class RecurringTransactionProcessor
  Result = Struct.new(:success?, :transaction, :occurrence, :error, keyword_init: true)

  class ProcessingError < StandardError; end

  class << self
    def call(recurring_transaction:, amount:, date:)
      amount = normalize_amount(amount)
      date = coerce_date(date)

      return failure("Recurring transaction is inactive.") unless recurring_transaction.active?
      return failure("Amount must be greater than zero.") if amount.nil? || amount <= 0
      return failure("A valid transaction date is required.") if date.nil?

      period = date.strftime("%Y-%m")

      if recurring_transaction.occurrences.exists?(period: period)
        return failure("Already processed for #{Date.new(date.year, date.month).strftime('%B %Y')}.")
      end

      transaction = nil
      occurrence = nil

      ActiveRecord::Base.transaction do
        transaction = build_transaction(recurring_transaction, amount, date)
        transaction.save!

        occurrence = recurring_transaction.occurrences.create!(
          transaction: transaction,
          transaction_date: date,
          period: period
        )
      end

      Result.new(success?: true, transaction: transaction, occurrence: occurrence, error: nil)
    rescue ActiveRecord::RecordNotUnique => e
      raise if e.message.exclude?("index_recurring_transactions_on_period")

      failure("Already processed for this month.")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      failure(e.record.errors.full_messages.to_sentence.presence || "Could not create the transaction.")
    end

    private

    def build_transaction(recurring_transaction, amount, date)
      attributes = {
        user: recurring_transaction.user,
        category: recurring_transaction.category,
        amount: amount,
        description: recurring_transaction.description,
        date: date,
        frequency: "one_time"
      }

      if recurring_transaction.income?
        Income.new(attributes)
      else
        Expense.new(attributes)
      end
    end

    def normalize_amount(value)
      return value.to_d if value.is_a?(Numeric)
      return nil if value.blank?

      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def coerce_date(value)
      return value if value.is_a?(Date)
      return value.to_date if value.respond_to?(:to_date)

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def failure(message)
      Result.new(success?: false, transaction: nil, occurrence: nil, error: message)
    end
  end
end
