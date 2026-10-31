# frozen_string_literal: true

module Mcp
  module Tools
    module Pockets
      # CreatePocketTool
      # Creates the MoneySource that holds assigned money. Targets belong to
      # goals, not to the pocket itself.
      class CreatePocketTool < Mcp::ApplicationTool
        tool_name "create_pocket"
        description "Create a pocket. Savings targets belong to goals, not to the pocket."
        requires_scope :write

        arguments do
          required(:name).filled(:string).description "Pocket name."
          optional(:idempotency_key).filled(:string).description "UUID to make retries safe."
        end

        def call(name:, idempotency_key: nil)
          key = idempotency_key!(idempotency_key)

          data = Mcp::Idempotency.run(
            user: user, key: key, tool: self.class.tool_name, arguments: { name: name }
          ) do
            pocket = user.money_sources.create!(name: name, kind: "pocket")
            Mcp::Presenters::PocketPresenter.new(pocket).as_json
          end

          success(data)
        rescue ActiveRecord::RecordInvalid => e
          raise Mcp::Error.new("INVALID_ARGUMENT", e.record.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
