# frozen_string_literal: true

# McpToolInvocation
# Audit trail for MCP calls that can change data. Argument values are never
# stored: only their keys, the affected resource and the outcome.
#
# Associations: belongs_to :user, :mcp_access_token (optional)
class McpToolInvocation < ApplicationRecord
  STATUSES = %w[succeeded failed].freeze

  belongs_to :user
  belongs_to :mcp_access_token, optional: true

  validates :tool_name, presence: true
  validates :status, inclusion: { in: STATUSES }
end
