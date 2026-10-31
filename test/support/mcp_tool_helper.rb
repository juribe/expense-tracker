# frozen_string_literal: true

# Invokes an MCP tool directly with a request-scoped user, mirroring what
# Mcp::EndpointController sets up after token authentication.
module McpToolHelper
  def invoke_tool(tool_class, user:, token: nil, **arguments)
    Mcp::Current.user = user
    Mcp::Current.scopes = %w[read write]
    Mcp::Current.token = token
    result, = tool_class.new.call_with_schema_validation!(**arguments)
    JSON.parse(result[:content].first[:text])
  ensure
    Mcp::Current.reset
  end
end
