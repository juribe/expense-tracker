# frozen_string_literal: true

module Mcp
  module Tools
    module SavingsGoals
      # CreateSavingsGoalTool
      # Creates a goal. Advanced accounts keep the pocket-backed behavior;
      # simple accounts create virtual goals without a Money Source.
      class CreateSavingsGoalTool < Mcp::ApplicationTool
        tool_name "create_savings_goal"
        description "Create a savings goal. Advanced accounts use a pocket; simple accounts create a virtual goal."
        requires_scope :write

        arguments do
          required(:name).filled(:string).description "Goal name."
          required(:target_amount).filled.description "Amount to reach."
          optional(:pocket_id).filled(:string).description "Pocket UUID for advanced accounts."
          optional(:target_date).filled(:string).description "ISO target date (YYYY-MM-DD)."
          optional(:category).filled(:string, included_in?: Goal::CATEGORIES).description "Optional goal category."
          optional(:priority).filled(:integer, included_in?: Goal::PRIORITIES.values).description "0 low, 1 medium, 2 high."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(name:, target_amount:, pocket_id: nil, target_date: nil, category: nil, priority: nil,
                 idempotency_key: nil)
          pocket = pocket_id.present? ? find_pocket!(pocket_id) : nil
          target = positive_amount!(target_amount)
          due_on = target_date.present? ? required_date!(target_date, field: "target_date") : nil
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name,
            arguments: { name: name, target_amount: target.to_s("F"), pocket_id: pocket&.id,
                         target_date: due_on&.iso8601, category: category, priority: priority }
          ) do
            attributes = { name: name, target_amount: target, target_date: due_on }
            attributes[:pocket] = pocket if pocket
            attributes[:category] = category if category.present?
            attributes[:priority] = priority unless priority.nil?
            goal = user.goals.create!(attributes)
            Mcp::Presenters::GoalPresenter.new(goal).as_json
          end

          success(data)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
