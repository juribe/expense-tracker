# frozen_string_literal: true

module Mcp
  module Presenters
    # GoalPresenter
    # Savings goal progress. Saved money is the sum of its pocket allocations,
    # never a stored value.
    class GoalPresenter
      include Mcp::Presenters::Money

      def initialize(goal)
        @goal = goal
      end

      def as_json
        {
          id: goal.id,
          name: goal.name,
          pocket: goal.pocket && { id: goal.pocket.id, name: goal.pocket.name },
          target_amount: money(goal.target_amount),
          saved_amount: money(goal.saved_amount),
          remaining_amount: money(goal.remaining_amount),
          progress_percentage: goal.progress_percentage.to_f.round(1),
          target_date: goal.target_date&.iso8601,
          required_monthly_contribution: money(goal.required_monthly_contribution),
          status: goal.status,
          health: goal.health.to_s,
          priority: goal.priority,
          category: goal.category
        }.compact
      end

      private

      attr_reader :goal
    end
  end
end
