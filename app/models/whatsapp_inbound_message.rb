# frozen_string_literal: true

# Registry of already-processed WhatsApp inbound message ids. The unique
# index on mid makes webhook re-deliveries and concurrent jobs idempotent:
# callers insert-or-skip before processing a message.
class WhatsappInboundMessage < ApplicationRecord
  # Returns true when this caller owns the message (first insert), false when
  # another delivery/job already claimed it.
  def self.claim!(mid)
    return false if mid.blank?

    create!(mid: mid, processed_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end
end
