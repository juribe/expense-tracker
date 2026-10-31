# frozen_string_literal: true

# McpIdempotencyRecord
# Remembers a completed write per user and idempotency key so client retries
# never create a duplicate expense, transfer or payment.
#
# Associations: belongs_to :user
class McpIdempotencyRecord < ApplicationRecord
  belongs_to :user

  validates :idempotency_key, presence: true, uniqueness: { scope: :user_id }
  validates :tool_name, :request_digest, presence: true
end
