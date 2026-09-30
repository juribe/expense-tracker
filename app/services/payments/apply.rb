# frozen_string_literal: true

module Payments
  # Applies an existing Expense to a debt with a manual distribution.
  # Never creates an Expense — the Expense already exists; the Payment is
  # only its accounting application to the debt target.
  #
  #   Payments::Apply.call(
  #     user: user, money_source: mortgage, expense: expense,
  #     distribution: { principal_amount: "900.000", ... }
  #   )
  class Apply
    class << self
      # payment: the already-persisted Payment being edited; nil to create.
      def call(user:, money_source:, expense:, distribution: {}, payment: nil)
        new(user: user, money_source: money_source, expense: expense,
            distribution: distribution, payment: payment).call
      end
    end

    def initialize(user:, money_source:, expense:, distribution: {}, payment: nil)
      @user = user
      @money_source = money_source
      @expense = expense
      @distribution = (distribution || {}).to_h.stringify_keys
      @payment = payment
    end

    def call
      payment = @payment || Payment.new(user: user, expense: expense,
                                        money_source: money_source, amount: amount)
      payment.assign_attributes(distribution_attributes)
      ActiveRecord::Base.transaction do
        payment.save!
      end
      ServiceResult.success(payment)
    rescue ActiveRecord::RecordNotUnique
      ServiceResult.error(duplicate_message)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.error(e.record.errors.full_messages)
    end

    private

    attr_reader :user, :money_source, :expense

    def distribution_attributes
      {
        principal_amount: money_component(:principal_amount),
        interest_amount: money_component(:interest_amount),
        insurance_amount: money_component(:insurance_amount),
        other_amount: money_component(:other_amount)
      }
    end

    def amount
      expense.amount.to_d.abs
    end

    def money_component(key)
      normalized = MoneyFormat.normalize(@distribution[key.to_s])
      return 0.to_d if normalized.blank?

      BigDecimal(normalized.to_s)
    rescue ArgumentError, TypeError
      0.to_d
    end

    def duplicate_message
      I18n.t("payments.duplicate")
    end
  end
end
