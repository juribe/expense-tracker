# frozen_string_literal: true

module Mcp
  # Request-scoped identity for the authenticated MCP caller. Populated by
  # Mcp::EndpointController after token authentication and reset by Rails
  # after every request.
  class Current < ActiveSupport::CurrentAttributes
    attribute :user, :scopes, :token
  end
end
