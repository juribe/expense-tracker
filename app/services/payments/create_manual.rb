# frozen_string_literal: true

module Payments
  # Creates a manual debt payment in one step: the Expense (the cash out from
  # the funding source) plus its application to the debt via Payments::Apply,
  # which also links the expense to the debt's recurring payment template
  # (RecurringLink) so Día de Cuadre stops listing the cuota as pending.
  #
  # Mirrors the statement import's payment (Statements::Confirmation#apply_payment)
  # but from user-entered data. The distribution must sum to the amount; any
  # failure rolls everything back, so an orphan expense is never left behind.
  #
  #   Payments::CreateManual.call(
  #     user: user, money_source: card, amount: "1.500.000", date: Date.current,
  #     description: "Cuota", category_id: 3, funding_money_source_id: 1,
  #     distribution: { principal_amount: "900.000", interest_amount: "600.000" }
  #   ) => ServiceResult(payment)
  class CreateManual
    class << self
      def call(user:, money_source:, amount:, date:, description:, category_id:,
               distribution: {}, funding_money_source_id: nil, idempotency_key: nil)
        new(user: user, money_source: money_source, amount: amount, date: date,
            description: description, category_id: category_id, distribution: distribution,
            funding_money_source_id: funding_money_source_id,
            idempotency_key: idempotency_key).call
      end
    end

    def initialize(user:, money_source:, amount:, date:, description:, category_id:,
                   distribution: {}, funding_money_source_id: nil, idempotency_key: nil)
      @user = user
      @money_source = money_source
      @amount = amount
      @date = date
      @description = description
      @category_id = category_id
      @distribution = (distribution || {}).to_h
      @funding_money_source_id = funding_money_source_id
      @idempotency_key = UuidParams.normalize(idempotency_key)
    end

    def call
      return ServiceResult.error([ I18n.t("payments.manual.invalid_target") ]) unless @money_source&.debt_payment_target?

      category = @category_id.present? ? Category.for_user(@user).find_by(id: @category_id) : nil
      return ServiceResult.error([ I18n.t("payments.manual.category_required") ]) if category.nil?

      funding = resolve_funding_source
      return ServiceResult.error([ I18n.t("payments.manual.funding_invalid") ]) if funding == :invalid

      # The browser can repeat this request (double submit, retry, stale JS):
      # a key already used by this user means the payment is done — return it
      # instead of charging the same payment twice.
      if (existing = payment_for_key)
        return ServiceResult.success(existing)
      end

      payment = nil
      ActiveRecord::Base.transaction do
        expense = Expenses::Create.call(
          user: @user,
          amount: MoneyFormat.normalize(@amount),
          description: description_text,
          category: category,
          occurred_at: @date,
          source: "manual",
          money_source: funding,
          idempotency_key: @idempotency_key
        )
        result = Payments::Apply.call(user: @user, money_source: @money_source,
                                      expense: expense, distribution: @distribution,
                                      expense_created: true)
        raise Rollback, result.errors unless result.success?

        payment = result.result
      end
      ServiceResult.success(payment)
    rescue Expenses::Create::Invalid => e
      ServiceResult.error([ e.message ])
    rescue Rollback => e
      ServiceResult.error(e.errors)
    rescue ActiveRecord::RecordNotUnique
      # Two identical concurrent requests: the unique index on
      # transactions.idempotency_key let only one create the expense.
      existing = payment_for_key
      existing ? ServiceResult.success(existing) : raise
    end

    private

    class Rollback < StandardError
      attr_reader :errors

      def initialize(errors)
        super(Array(errors).to_sentence)
        @errors = Array(errors)
      end
    end

    def description_text
      @description.presence || I18n.t("payments.description_fallback")
    end

    # The expense (with its payment) created for this idempotency key, if any.
    # Nothing else can claim the same key: the unique index enforces it.
    def payment_for_key
      return nil if @idempotency_key.blank?

      expense = Transaction.find_by(user: @user, idempotency_key: @idempotency_key)
      return nil unless expense

      Payment.find_by(expense_id: expense.id)
    end

    # A payment must always know where its money came from; the missing
    # source (and a debt / inactive source / the paid debt) both fail.
    def resolve_funding_source
      id = @funding_money_source_id.presence
      return :invalid if id.nil?

      source = @user.money_sources.find_by(id: id)
      return :invalid if source.nil?
      return :invalid unless source.active? && source.payment_source? && source.id != @money_source.id

      source
    end
  end
end
