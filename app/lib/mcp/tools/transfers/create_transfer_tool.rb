# frozen_string_literal: true

module Mcp
  module Tools
    module Transfers
      # CreateTransferTool
      # Moves money between two of the user's sources using the Transfer model,
      # which owns every balance, debt and pocket rule.
      class CreateTransferTool < Mcp::ApplicationTool
        tool_name "create_transfer"
        description "Move money between two money sources."
        requires_scope :write

        arguments do
          required(:amount).filled.description "Positive amount."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          required(:source_id).filled(:string).description "Origin money source UUID."
          required(:destination_id).filled(:string).description "Destination money source UUID."
          optional(:description).filled(:string).description "Short note."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(amount:, date:, source_id:, destination_id:, description: nil, idempotency_key: nil)
          from = find_money_source!(source_id)
          to = find_money_source!(destination_id)
          occurred_on = required_date!(date)
          parsed_amount = positive_amount!(amount)
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { amount: parsed_amount.to_s("F"), date: occurred_on.iso8601,
                         source_id: from.id, destination_id: to.id, description: description }
          ) do
            transfer = user.transfers.create!(
              from_source: from, to_source: to, amount: parsed_amount,
              date: occurred_on, note: description
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
