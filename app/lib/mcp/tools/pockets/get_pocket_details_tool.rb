# frozen_string_literal: true

module Mcp
  module Tools
    module Pockets
      # GetPocketDetailsTool
      # One pocket plus the goals reserving money inside it.
      class GetPocketDetailsTool < Mcp::ApplicationTool
        tool_name "get_pocket_details"
        description "Return one pocket with balance, allocated money and its goals."
        requires_scope :read

        arguments do
          required(:pocket_id).filled(:string).description "Pocket UUID."
        end

        def call(pocket_id:)
          pocket = user.money_sources.includes(:goal_allocations).find(UuidParams.normalize(pocket_id))
          raise Mcp::Error.new("INVALID_POCKET", "The selected money source is not a pocket.") unless pocket.pocket?

          data = Mcp::Presenters::PocketPresenter.new(pocket).as_json.merge(
            goals: pocket.goals.includes(:pocket, :goal_allocations).order(:created_at)
                        .map { |goal| Mcp::Presenters::GoalPresenter.new(goal).as_json }
          )
          success(data)
        end
      end
    end
  end
end
