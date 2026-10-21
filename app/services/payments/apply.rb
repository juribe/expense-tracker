# frozen_string_literal: true

module Payments
  # Applies an expense to a debt with a manual distribution. The Payment is
  # the accounting application of the expense (an existing Transaction) to
  # the debt target; it never creates one.
  #
  # expense_created marks payments whose expense was born in the same step
  # (Payments::CreateManual, Statements::Confirmation): they must revert the
  # expense too when destroyed. Payments over pre-existing expenses keep it
  # false, so the expense survives the revert.
  #
  #   Payments::Apply.call(
  #     user: user, money_source: mortgage, expense: expense,
  #     distribution: { principal_amount: "900.000", ... },
  #     expense_created: true
  #   )
  class Apply
    class << self
      # payment: the already-persisted Payment being edited; nil to create.
      def call(user:, money_source:, expense:, distribution: {}, payment: nil,
               expense_created: false)
        new(user: user, money_source: money_source, expense: expense,
            distribution: distribution, payment: payment,
            expense_created: expense_created).call
      end
    end

    def initialize(user:, money_source:, expense:, distribution: {}, payment: nil,
                   expense_created: false)
      @user = user
      @money_source = money_source
      @expense = expense
      @distribution = (distribution || {}).to_h.stringify_keys
      @payment = payment
      @expense_created = expense_created
    end

    def call
      payment = @payment || Payment.new(user: user, expense: expense,
                                        money_source: money_source, amount: amount)
      payment.assign_attributes(distribution_attributes)
      payment.created_expense = true if @payment.nil? && @expense_created
      ActiveRecord::Base.transaction do
        payment.save!
        # Keep Día de Cuadre in sync: the cuota paid here is usually the
        # expense of its recurring template. Non-blocking — if the
        # assignment is ambiguous it is skipped and stays pending in the
        # cuadre's manual "Asignar" flow.
        RecurringLink.call(user: user, expense: expense, money_source: money_source)
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
