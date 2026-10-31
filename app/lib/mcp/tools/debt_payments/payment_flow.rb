# frozen_string_literal: true

module Mcp
  module Tools
    module DebtPayments
      # PaymentFlow
      # Shared write flow for the credit-card and debt payment tools: validate
      # ownership and capabilities, then delegate to Mcp::DebtPaymentCreation.
      module PaymentFlow
        private

        def pay_debt(target:, funding:, amount:, date:, description:, category_id:,
                     components:, idempotency_key:)
          funding = ensure_payment_source!(funding)
          if funding.id == target.id
            raise Mcp::Error.new("INVALID_MONEY_SOURCE", "A debt cannot be paid from itself.")
          end

          occurred_on = required_date!(date)
          parsed_amount = positive_amount!(amount)
          key = idempotency_key!(idempotency_key)
          category = category_id.present? ? find_category!(category_id, type: "expense") : Mcp::DebtPaymentCreation.default_category
          distribution = Mcp::DebtPaymentCreation.distribution_for(amount: parsed_amount, components: components)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { amount: parsed_amount.to_s("F"), date: occurred_on.iso8601,
                         target_id: target.id, funding_id: funding.id,
                         description: description, category_id: category.id,
                         distribution: distribution }
          ) do
            payment = Mcp::DebtPaymentCreation.new(
              user: user, target: target, funding: funding, amount: parsed_amount,
              date: occurred_on, description: description, category: category,
              distribution: distribution, idempotency_key: key
            ).call
            Mcp::Presenters::PaymentPresenter.new(payment).as_json
          end

          success(data)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new(record_error_code(e.record), e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
