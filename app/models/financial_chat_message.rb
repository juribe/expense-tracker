# A single message inside a user's FinancialChat.
#
# Roles: "user" (asked question) or "assistant" (LLM answer).
# Statuses track the asynchronous workflow:
#   sent        - user message persisted, not yet processed
#   processing  - assistant placeholder created, analysis enqueued
#   streaming   - assistant content arriving through Action Cable
#   complete    - final assistant content persisted
#   failed      - analysis failed; error_message holds the reason
class FinancialChatMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze
  STATUSES = %w[sent processing streaming complete failed].freeze

  belongs_to :financial_chat

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :content, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :complete, -> { where(status: "complete") }

  def user?
    role == "user"
  end

  def assistant?
    role == "assistant"
  end

  def failed?
    status == "failed"
  end

  # Serialization contract for the browser client (broadcasts and JSON API).
  def client_payload
    {
      id: id,
      role: role,
      content: content,
      status: status,
      error_message: error_message,
      created_at: created_at&.strftime("%H:%M")
    }
  end
end
