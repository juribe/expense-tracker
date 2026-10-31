# frozen_string_literal: true

module Mcp
  module Tools
    module Pockets
      # GetPocketsTool
      # Pockets with real balance and the part reserved by goals.
      class GetPocketsTool < Mcp::ApplicationTool
        tool_name "get_pockets"
        description "List pockets with balance, allocated and unallocated money."
        requires_scope :read

        def call
          pockets = user.money_sources.active.pockets.includes(:goal_allocations).order(:name)
                        .map { |source| Mcp::Presenters::PocketPresenter.new(source).as_json }

          success(pockets: pockets)
        end
      end
    end
  end
end
