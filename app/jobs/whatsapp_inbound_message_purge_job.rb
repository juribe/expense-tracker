# frozen_string_literal: true

# Drops WhatsApp message-id claims that are past the redelivery window.
class WhatsappInboundMessagePurgeJob < ApplicationJob
  queue_as :default

  def perform
    WhatsappInboundMessage.stale.delete_all
  end
end
