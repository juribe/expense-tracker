# frozen_string_literal: true

module Mcp
  module Tools
    module Pockets
      # AllocateToPocketTool
      # Assigns real money to a pocket with a Transfer (money must leave a
      # real source first; a pocket is never funded magically).
      class AllocateToPocketTool < Mcp::ApplicationTool
        tool_name "allocate_to_pocket"
        description "Move money from an account or cash into a pocket."
        requires_scope :write

        arguments do
          required(:pocket_id).filled(:string).description "Pocket UUID."
          required(:amount).filled.description "Positive amount."
          required(:source_id).filled(:string).description "Origin money source UUID."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(pocket_id:, amount:, source_id:, date:, idempotency_key: nil)
          pocket = find_pocket!(pocket_id)
          source = find_money_source!(source_id)
          occurred_on = required_date!(date)
          parsed_amount = positive_amount!(amount)
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { amount: parsed_amount.to_s("F"), date: occurred_on.iso8601,
                         pocket_id: pocket.id, source_id: source.id }
          ) do
            transfer = user.transfers.create!(
              from_source: source, to_source: pocket, amount: parsed_amount, date: occurred_on
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
