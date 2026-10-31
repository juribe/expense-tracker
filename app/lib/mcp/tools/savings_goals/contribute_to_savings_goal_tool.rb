# frozen_string_literal: true

module Mcp
  module Tools
    module SavingsGoals
      # ContributeToSavingsGoalTool
      # Reserves pocket money for a goal. With a source, the money is first
      # moved into the pocket with a Transfer; the allocation itself never
      # moves money.
      class ContributeToSavingsGoalTool < Mcp::ApplicationTool
        tool_name "contribute_to_savings_goal"
        description "Reserve money for a savings goal. With source_id, first move that money into the goal's pocket."
        requires_scope :write

        arguments do
          required(:goal_id).filled(:string).description "Goal UUID."
          required(:amount).filled.description "Positive amount."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          optional(:source_id).filled(:string).description "Account or cash UUID to fund the contribution."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(goal_id:, amount:, date:, source_id: nil, idempotency_key: nil)
          goal = user.goals.includes(:pocket).find(UuidParams.normalize(goal_id))
          parsed_amount = positive_amount!(amount)
          occurred_on = required_date!(date)
          source = source_id.present? ? find_money_source!(source_id) : nil
          ensure_contribution_source!(source) if source
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { goal_id: goal.id, amount: parsed_amount.to_s("F"),
                         date: occurred_on.iso8601, source_id: source&.id }
          ) do
            transfer = nil
            ActiveRecord::Base.transaction do
              if source
                transfer = user.transfers.create!(
                  from_source: source, to_source: goal.pocket, amount: parsed_amount, date: occurred_on
                )
              end
              allocation = goal.goal_allocations.create!(amount: parsed_amount, date: occurred_on)
              allocation_payload(allocation, goal, transfer)
            end
          end

          success(data)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new(movement_error_code(e.record), e.record.errors.full_messages.to_sentence)
        end

        private

        def ensure_contribution_source!(source)
          return if source.payment_source? && !source.debt?

          raise Mcp::Error.new("INVALID_MONEY_SOURCE",
                               "A contribution must come from an account, cash, wallet or debit card.")
        end

        def allocation_payload(allocation, goal, transfer)
          {
            id: allocation.id,
            amount: Mcp::Presenters::Money.money(allocation.amount),
            date: allocation.date.iso8601,
            goal: { id: goal.id, name: goal.name,
                    saved_amount: Mcp::Presenters::Money.money(goal.reload.saved_amount) },
            transfer: transfer && { id: transfer.id, amount: Mcp::Presenters::Money.money(transfer.amount) }
          }
        end
      end
    end
  end
end
