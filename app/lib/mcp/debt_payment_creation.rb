# frozen_string_literal: true

module Mcp
  # DebtPaymentCreation
  # Thin adapter over Payments::CreateManual, the existing mechanism that
  # creates the funding expense and applies it to a debt in one transaction.
  #
  # Example: Mcp::DebtPaymentCreation.new(user: user, target: card,
  #   funding: account, amount: 300_000, date: Date.current, description: "Abono",
  #   category: category, distribution: { principal_amount: "300000" },
  #   idempotency_key: key).call
  class DebtPaymentCreation
    def initialize(user:, target:, funding:, amount:, date:, description:, category:, distribution:, idempotency_key: nil)
      @user = user
      @target = target
      @funding = funding
      @amount = amount
      @date = date
      @description = description
      @category = category
      @distribution = distribution
      @idempotency_key = idempotency_key
    end

    def call
      result = ::Payments::CreateManual.call(
        user: @user,
        money_source: @target,
        amount: @amount,
        date: @date,
        description: @description,
        category_id: @category.id,
        funding_money_source_id: @funding.id,
        idempotency_key: @idempotency_key,
        distribution: @distribution
      )
      return result.result if result.success?

      raise Mcp::Error.new(error_code(result.errors), result.errors.to_sentence)
    end

    def self.default_category
      Category.find_or_create_by!(
        name: I18n.t("categories.debt_payments"),
        is_default: true,
        category_type: "expense"
      )
    end

    # Without an explicit split, the whole payment reduces principal — the
    # same default the web payment form starts from.
    def self.distribution_for(amount:, components: {})
      return { principal_amount: amount.to_s("F") } if components.values.all?(&:blank?)

      components.transform_values { |value| value.blank? ? "0" : MoneyFormat.normalize(value) }
    end

    private

    def error_code(errors)
      messages = Array(errors).join(" ")
      return "INVALID_DEBT" if messages.include?(I18n.t("payments.manual.invalid_target"))
      return "INVALID_MONEY_SOURCE" if messages.include?(I18n.t("payments.manual.funding_invalid"))
      return "INVALID_CATEGORY" if messages.include?(I18n.t("payments.manual.category_required"))

      "INVALID_ARGUMENT"
    end
  end
end
