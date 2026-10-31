# frozen_string_literal: true

module Mcp
  module Tools
    module SavingsGoals
      # UpdateSavingsGoalTool
      # Changes the goal's definition, never its saved money directly.
      class UpdateSavingsGoalTool < Mcp::ApplicationTool
        tool_name "update_savings_goal"
        description "Update a savings goal's name, target, date, category, priority or status."
        requires_scope :write

        arguments do
          required(:goal_id).filled(:string).description "Goal UUID."
          optional(:name).filled(:string).description "New name."
          optional(:target_amount).filled.description "New target amount."
          optional(:target_date).filled(:string).description "ISO target date (YYYY-MM-DD)."
          optional(:category).filled(:string, included_in?: Goal::CATEGORIES).description "Goal category."
          optional(:priority).filled(:integer, included_in?: Goal::PRIORITIES.values).description "0 low, 1 medium, 2 high."
          optional(:status).filled(:string, included_in?: Goal::STATUSES).description "active or archived."
          optional(:pocket_id).filled(:string).description "Move the goal to another pocket (only without allocations)."
        end

        def call(goal_id:, name: nil, target_amount: nil, target_date: nil, category: nil,
                 priority: nil, status: nil, pocket_id: nil)
          goal = user.goals.includes(:pocket, :goal_allocations).find(UuidParams.normalize(goal_id))
          attributes = {}
          attributes[:name] = name if name.present?
          attributes[:target_amount] = positive_amount!(target_amount) if target_amount.present?
          attributes[:target_date] = required_date!(target_date, field: "target_date") if target_date.present?
          attributes[:category] = category if category.present?
          attributes[:priority] = priority unless priority.nil?
          attributes[:status] = status if status.present?
          attributes[:pocket] = find_pocket!(pocket_id) if pocket_id.present?

          goal.update!(attributes) if attributes.any?
          success(Mcp::Presenters::GoalPresenter.new(goal.reload).as_json)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
