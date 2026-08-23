# frozen_string_literal: true

# Tracks every email examined by the import pipeline so each message is only
# processed once across all providers. The [provider, message_id] unique index
# makes duplicate prevention race-safe.
class ProcessedEmail < ApplicationRecord
  STATUSES = %w[processed ignored needs_review failed].freeze

  belongs_to :user
  belongs_to :expense, optional: true

  validates :provider, presence: true, inclusion: { in: %w[gmail] }
  validates :message_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :message_id, uniqueness: { scope: :provider }

  scope :gmail, -> { where(provider: "gmail") }
  scope :needs_review, -> { where(status: "needs_review") }
  scope :failed, -> { where(status: "failed") }
  scope :imported, -> { processed.where.not(expense_id: nil) }
  scope :processed, -> { where(status: "processed") }
  scope :ignored, -> { where(status: "ignored") }

  # Parsed extraction payload (transactions pending review, debug info...).
  def payload_data
    JSON.parse(payload.to_s)
  rescue JSON::ParserError
    {}
  end

  def failed?
    status == "failed"
  end

  def needs_review?
    status == "needs_review"
  end
end
