# frozen_string_literal: true

class WhatsappWebhookJob < ApplicationJob
  queue_as :default

  def perform(raw_body)
    Rails.logger.info("[WhatsappWebhookJob] Received webhook (#{raw_body.to_s.bytesize} bytes)")
    WebHookHandler::WhatsappService.call(raw_body: raw_body)
    Rails.logger.info("[WhatsappWebhookJob] Webhook processed")
  rescue => e
    Rails.logger.error("[WhatsappWebhookJob] Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise e
  end
end
