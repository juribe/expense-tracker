# frozen_string_literal: true

module Mcp
  module Tools
    module Pockets
      # UpdatePocketTool
      # Renames a pocket or activates/deactivates it. It never changes money.
      class UpdatePocketTool < Mcp::ApplicationTool
        tool_name "update_pocket"
        description "Rename a pocket or change its active state."
        requires_scope :write

        arguments do
          required(:pocket_id).filled(:string).description "Pocket UUID."
          optional(:name).filled(:string).description "New name."
          optional(:active).filled(:bool).description "Whether the pocket is active."
        end

        def call(pocket_id:, name: nil, active: nil)
          pocket = find_pocket!(pocket_id)
          attributes = {}
          attributes[:name] = name if name.present?
          attributes[:active] = active unless active.nil?

          pocket.update!(attributes) if attributes.any?
          success(Mcp::Presenters::PocketPresenter.new(pocket.reload).as_json)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
