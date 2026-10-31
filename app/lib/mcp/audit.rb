# frozen_string_literal: true

module Mcp
  # Audit
  # Persists an MCP write invocation without storing argument values or
  # financial content. Audit failures never break the operation.
  module Audit
    module_function

    def record(user:, tool_name:, status:, token: nil, error_code: nil, resource_id: nil, argument_keys: [])
      McpToolInvocation.create!(
        user: user,
        mcp_access_token: token,
        tool_name: tool_name,
        status: status,
        error_code: error_code,
        resource_id: resource_id,
        argument_keys: Array(argument_keys).map(&:to_s)
      )
    rescue StandardError => e
      Rails.logger.error("[mcp] audit failed for #{tool_name}: #{e.class}: #{e.message}")
    end
  end
end
