# frozen_string_literal: true

# MailInboundDelivery
# Durable receipt of a provider webhook before MIME parsing or API fetching.
#
# Associations: belongs_to :user, belongs_to :processed_email (optional)
# Methods: handling!, handled!, failed!
#
# Example: MailInboundDelivery.find(id).handling!
class MailInboundDelivery < ApplicationRecord
  PROVIDERS = %w[cloudflare resend].freeze
  STATUSES = %w[received handling handled failed].freeze
  STALE_HANDLING_TIMEOUT = 30.minutes

  belongs_to :user
  belongs_to :processed_email, optional: true

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :external_id, presence: true, uniqueness: { scope: :provider }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :received, -> { where(status: "received") }
  scope :failed, -> { where(status: "failed") }
  scope :stale_handling, -> { where(status: "handling").where(updated_at: ...STALE_HANDLING_TIMEOUT.ago) }

  def handling!
    update!(status: "handling", attempts: attempts + 1, last_error: nil)
  end

  # A handled delivery no longer needs the raw MIME or provider payload: the
  # normalized message lives in the linked ProcessedEmail. Routing and dedup
  # columns (provider, external_id, user, status) stay intact.
  def handled!(processed_email)
    update!(
      status: "handled",
      processed_email: processed_email,
      processed_at: Time.current,
      last_error: nil,
      raw_body: nil,
      headers: {},
      params: {}
    )
  end

  def failed!(error)
    update!(status: "failed", last_error: error.to_s.truncate(500), processed_at: Time.current)
  end

  # Drops stored email content without changing the delivery lifecycle state.
  def purge_email_content!
    update_columns(raw_body: nil, headers: {}, params: {}, updated_at: Time.current)
  end
end
