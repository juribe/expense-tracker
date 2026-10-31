# frozen_string_literal: true

module Mcp
  module Tools
    module SavingsGoals
      # GetSavingsGoalsTool
      # Savings goals with target, saved, remaining and progress.
      class GetSavingsGoalsTool < Mcp::ApplicationTool
        tool_name "get_savings_goals"
        description "List savings goals with target amount, saved amount, remaining amount and progress."
        requires_scope :read

        STATUSES = %w[active archived all].freeze

        arguments do
          optional(:status).filled(:string, included_in?: STATUSES)
            .description "active (default), archived or all."
        end

        def call(status: "active")
          scope =
            case status
            when "archived" then user.goals.where(status: "archived")
            when "all" then user.goals
            else user.goals.active
            end

          goals = scope.includes(:pocket, :goal_allocations).order(:created_at)
                       .map { |goal| Mcp::Presenters::GoalPresenter.new(goal).as_json }

          success(savings_goals: goals)
        end
      end
    end
  end
end
