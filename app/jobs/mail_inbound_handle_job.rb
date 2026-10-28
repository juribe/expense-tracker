# frozen_string_literal: true

# Normalizes one durable inbound delivery (MIME parse or Resend API fetch)
# and enqueues the expense-processing job. The HTTP webhook only enqueues this.
class MailInboundHandleJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    delivery = MailInboundDelivery.find_by(id: job.arguments.first)
    delivery&.failed!(error)
    # No retry remains: the raw message can no longer be processed.
    delivery&.purge_email_content!
  end

  def perform(delivery_id)
    delivery = MailInboundDelivery.find(delivery_id)
    if delivery.status == "handled"
      delivery.purge_email_content!
      return
    end

    delivery.handling!
    message = MailInboundService.new(provider: delivery.provider).handle_email(delivery)
    record, = MailInbound::Acceptance.new(delivery: delivery, message: message).call
    delivery.handled!(record)

    Rails.logger.info("[MailInboundHandleJob] delivery=#{delivery.id} provider=#{delivery.provider} status=handled")
  rescue MailInbound::InvalidPayload, MailInbound::UnknownRecipient, MailInbound::ConfigurationError => e
    delivery&.failed!(e)
    delivery&.purge_email_content!
    Rails.logger.warn("[MailInboundHandleJob] delivery=#{delivery_id} permanent failure: #{e.class}")
  rescue MailInbound::QueueError => e
    delivery&.failed!(e)
    raise
  rescue StandardError => e
    delivery&.failed!(e)
    raise
  end
end
