# frozen_string_literal: true

module Mcp
  module Presenters
    # CategoryPresenter
    # Compact category shape shared by MCP tools and resources.
    #
    # Example: Mcp::Presenters::CategoryPresenter.new(category).as_json
    class CategoryPresenter
      def initialize(category)
        @category = category
      end

      def as_json
        {
          id: category.id,
          name: category.name,
          type: category.category_type,
          parent_id: category.parent_id,
          default: category.default?,
          active: category.active
        }
      end

      private

      attr_reader :category
    end
  end
end
