# frozen_string_literal: true

module Mcp
  module Tools
    module SavingsGoals
      # GetSavingsGoalDetailsTool
      # One savings goal with its pocket.
      class GetSavingsGoalDetailsTool < Mcp::ApplicationTool
        tool_name "get_savings_goal_details"
        description "Return one savings goal with target, saved, remaining, progress and pocket."
        requires_scope :read

        arguments do
          required(:goal_id).filled(:string).description "Savings goal UUID."
        end

        def call(goal_id:)
          goal = user.goals.includes(:pocket, :goal_allocations).find(UuidParams.normalize(goal_id))
          success(Mcp::Presenters::GoalPresenter.new(goal).as_json)
        end
      end
    end
  end
end
