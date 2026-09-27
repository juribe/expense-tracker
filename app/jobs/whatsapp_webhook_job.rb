# frozen_string_literal: true
class WhatsappWebhookJob < ApplicationJob
  queue_as :default

  def perform(raw_body)
    WebHookHandler::WhatsappService.call(raw_body: raw_body)
  rescue => e
    Rails.logger.error("[WhatsappWebhookJob] Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise e
  end
end
