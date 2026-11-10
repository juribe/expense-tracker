module PaymentEngine
  # Auditable record of every provider notification. Unique by provider+event_id
  # so the same event is never processed twice. Payloads are redacted before
  # persistence and kept for audit and reprocessing.
  class WebhookEvent < ApplicationRecord
    STATUSES = %w[received processing processed failed ignored].freeze

    validates :provider, presence: true
    validates :event_id, presence: true, uniqueness: { scope: :provider }
    validates :status, inclusion: { in: STATUSES }

    scope :pending, -> { where(status: %w[received failed]) }
    scope :recent, -> { order(received_at: :desc) }

    def processed?
      status == "processed"
    end

    def ignored?
      status == "ignored"
    end

    def mark_processing!
      update!(status: "processing", attempts: attempts + 1)
    end

    def mark_processed!
      update!(status: "processed", processed_at: Time.current, error_message: nil)
    end

    def mark_ignored!(reason = nil)
      update!(status: "ignored", processed_at: Time.current, error_message: reason)
    end

    def mark_failed!(error)
      update!(status: "failed", error_message: error.to_s.truncate(1000))
    end
  end
end
