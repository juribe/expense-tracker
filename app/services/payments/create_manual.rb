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
               distribution: {}, funding_money_source_id: nil)
        new(user: user, money_source: money_source, amount: amount, date: date,
            description: description, category_id: category_id, distribution: distribution,
            funding_money_source_id: funding_money_source_id).call
      end
    end

    def initialize(user:, money_source:, amount:, date:, description:, category_id:,
                   distribution: {}, funding_money_source_id: nil)
      @user = user
      @money_source = money_source
      @amount = amount
      @date = date
      @description = description
      @category_id = category_id
      @distribution = (distribution || {}).to_h
      @funding_money_source_id = funding_money_source_id
    end

    def call
      return ServiceResult.error([ I18n.t("payments.manual.invalid_target") ]) unless @money_source&.debt_payment_target?

      category = @category_id.present? ? Category.for_user(@user).find_by(id: @category_id) : nil
      return ServiceResult.error([ I18n.t("payments.manual.category_required") ]) if category.nil?

      funding = resolve_funding_source
      return ServiceResult.error([ I18n.t("payments.manual.funding_invalid") ]) if funding == :invalid

      payment = nil
      ActiveRecord::Base.transaction do
        expense = Expenses::Create.call(
          user: @user,
          amount: MoneyFormat.normalize(@amount),
          description: description_text,
          category: category,
          occurred_at: @date,
          source: "manual",
          money_source: funding
        )
        result = Payments::Apply.call(user: @user, money_source: @money_source,
                                      expense: expense, distribution: @distribution)
        raise Rollback, result.errors unless result.success?

        payment = result.result
      end
      ServiceResult.success(payment)
    rescue Expenses::Create::Invalid => e
      ServiceResult.error([ e.message ])
    rescue Rollback => e
      ServiceResult.error(e.errors)
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

    # nil = no funding source (allowed); :invalid = a posted source that is not
    # a usable payment source (a debt, an inactive source, or the paid debt).
    def resolve_funding_source
      id = @funding_money_source_id.presence
      return nil if id.nil?

      source = @user.money_sources.find_by(id: id)
      return :invalid if source.nil?
      return :invalid unless source.active? && source.payment_source? && source.id != @money_source.id

      source
    end
  end
end
