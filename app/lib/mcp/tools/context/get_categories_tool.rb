# frozen_string_literal: true

module Mcp
  module Tools
    module Context
      # GetCategoriesTool
      # Lists the shared defaults plus the authenticated user's own categories.
      class GetCategoriesTool < Mcp::ApplicationTool
        tool_name "get_categories"
        description "List the expense and income categories available to the authenticated user."
        requires_scope :read

        arguments do
          optional(:category_type).filled(:string, included_in?: %w[expense income])
            .description "Filter by category type: expense or income."
        end

        def call(category_type: nil)
          categories = Category.for_user(user).active
          categories = categories.where(category_type: category_type) if category_type

          success(
            categories: categories.order(:category_type, :name)
                                  .map { |category| Mcp::Presenters::CategoryPresenter.new(category).as_json }
          )
        end
      end
    end
  end
end
