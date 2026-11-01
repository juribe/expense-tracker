# frozen_string_literal: true

# Tracks every email examined by the import pipeline so each message is only
# processed once across all providers. The [provider, message_id] unique index
# makes duplicate prevention race-safe: an import run claims a message by
# creating its row in "processing" state BEFORE doing extraction, so
# concurrent syncs see the claim and skip.
class ProcessedEmail < ApplicationRecord
  STATUSES = %w[queued processing processed ignored needs_review failed].freeze
  # Outcomes that must never be imported again. A later sync or a failed fetch
  # must not turn these rows back into retryable work.
  TERMINAL_STATUSES = %w[processed ignored needs_review].freeze

  belongs_to :user
  belongs_to :expense, optional: true

  validates :provider, presence: true, inclusion: { in: %w[gmail cloudflare resend] }
  validates :message_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :message_id, uniqueness: { scope: :provider }

  scope :gmail, -> { where(provider: "gmail") }
  scope :cloudflare, -> { where(provider: "cloudflare") }
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

  # Removes the normalized email from the payload once it has been processed.
  # Derived data needed later (subject/transactions of a needs_review row) is
  # preserved. Idempotent and safe for Gmail rows, which never store the email.
  def purge_email_content!
    return if payload.blank?

    data = payload_data
    return unless data.key?("email")

    data.delete("email")
    update_columns(payload: data.presence && JSON.generate(data), updated_at: Time.current)
  end

  def failed?
    status == "failed"
  end

  def needs_review?
    status == "needs_review"
  end
end
