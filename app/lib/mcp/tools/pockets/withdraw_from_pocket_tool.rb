# frozen_string_literal: true

module Mcp
  module Tools
    module Pockets
      # WithdrawFromPocketTool
      # Releases pocket money back into a real source with a Transfer. The
      # model refuses to leave goal reservations uncovered.
      class WithdrawFromPocketTool < Mcp::ApplicationTool
        tool_name "withdraw_from_pocket"
        description "Move money out of a pocket into an account or cash."
        requires_scope :write

        arguments do
          required(:pocket_id).filled(:string).description "Pocket UUID."
          required(:amount).filled.description "Positive amount."
          required(:destination_id).filled(:string).description "Destination money source UUID."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(pocket_id:, amount:, destination_id:, date:, idempotency_key: nil)
          pocket = find_pocket!(pocket_id)
          destination = find_money_source!(destination_id)
          occurred_on = required_date!(date)
          parsed_amount = positive_amount!(amount)
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { amount: parsed_amount.to_s("F"), date: occurred_on.iso8601,
                         pocket_id: pocket.id, destination_id: destination.id }
          ) do
            transfer = user.transfers.create!(
              from_source: pocket, to_source: destination, amount: parsed_amount, date: occurred_on
            )
            Mcp::Presenters::TransferPresenter.new(transfer).as_json
          end

          success(data)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new(movement_error_code(e.record), e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
