# frozen_string_literal: true

module Mcp
  module Tools
    module SavingsGoals
      # WithdrawFromSavingsGoalTool
      # Releases a goal reservation with a negative GoalAllocation. The money
      # stays in the pocket; withdrawing real cash is a pocket withdrawal.
      class WithdrawFromSavingsGoalTool < Mcp::ApplicationTool
        tool_name "withdraw_from_savings_goal"
        description "Release money reserved for a goal. The money stays in its pocket."
        requires_scope :write

        arguments do
          required(:goal_id).filled(:string).description "Goal UUID."
          required(:amount).filled.description "Positive amount to release."
          required(:date).filled(:string).description "ISO date (YYYY-MM-DD)."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(goal_id:, amount:, date:, idempotency_key: nil)
          goal = user.goals.includes(:pocket).find(UuidParams.normalize(goal_id))
          parsed_amount = positive_amount!(amount)
          occurred_on = required_date!(date)
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { goal_id: goal.id, amount: parsed_amount.to_s("F"), date: occurred_on.iso8601 }
          ) do
            allocation = goal.goal_allocations.create!(amount: -parsed_amount, date: occurred_on)
            {
              id: allocation.id,
              amount: Mcp::Presenters::Money.money(allocation.amount),
              date: allocation.date.iso8601,
              goal: { id: goal.id, name: goal.name,
                      saved_amount: Mcp::Presenters::Money.money(goal.reload.saved_amount) }
            }
          end

          success(data)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
