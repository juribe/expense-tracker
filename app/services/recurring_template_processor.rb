# frozen_string_literal: true

# Turns a recurring configuration into a real one-time transaction.
#
#   RecurringTemplateProcessor.call(
#     recurring_template: recurring_template,
#     amount: 6500.00,
#     date: Date.new(2026, 8, 18)
#   )
#
# Rules:
# * The recurring template must be active.
# * The period is derived from the given date ("YYYY-MM").
# * A recurring template can only be processed once per period.
# * Processing creates a normal Transaction
#   linked back to the template.
# * Everything runs inside a single database transaction.
class RecurringTemplateProcessor
  Result = Struct.new(:success?, :transaction, :error, keyword_init: true)

  class << self
    def call(recurring_template:, amount:, date:)
      amount = normalize_amount(amount)
      date = coerce_date(date)

      return failure("Recurring template is inactive.") unless recurring_template.active?
      return failure("Amount must be greater than zero.") if amount.nil? || amount <= 0
      return failure("A valid transaction date is required.") if date.nil?

      period_range = period_range_for(date)

      if recurring_template.transactions.where(date: period_range).exists?
        return failure("Already processed for #{date.strftime('%B %Y')}.")
      end

      transaction = nil

      ActiveRecord::Base.transaction do
        transaction = Transaction.new(
          user: recurring_template.user,
          category: recurring_template.category,
          amount: amount,
          description: recurring_template.description,
          date: date,
          kind: recurring_template.kind,
          recurring_template: recurring_template,
          source: "recurring_template"
        )
        transaction.save!
      end

      Result.new(success?: true, transaction: transaction, error: nil)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      failure(e.record.errors.full_messages.to_sentence.presence || "Could not create the transaction.")
    end

    private

    def normalize_amount(value)
      return value.to_d if value.is_a?(Numeric)
      return nil if value.blank?

      BigDecimal(value.to_s.delete(","))
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

    def period_range_for(date)
      date.beginning_of_month..date.end_of_month
    end

    def failure(message)
      Result.new(success?: false, transaction: nil, error: message)
    end
  end
end
