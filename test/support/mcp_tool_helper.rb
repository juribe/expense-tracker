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

  # Counts real SQL statements (schema and transaction control excluded) so a
  # test can prove a tool does not query once per record.
  def count_queries
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      count += 1
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end
