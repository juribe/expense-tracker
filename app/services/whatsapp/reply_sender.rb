# frozen_string_literal: true

require "net/http"

# Whatsapp::ReplySender
# Sends text replies back to a WhatsApp user through the Meta Cloud API, using
# the business phone number and system user token configured via ENV. Safe to
# call without credentials: it logs and no-ops instead of raising, so webhook
# processing never depends on outbound delivery.
#
# Example: Whatsapp::ReplySender.send_to("573001234567", "WhatsApp conectado ✅")
module Whatsapp
  class ReplySender
    GRAPH_URL = "https://graph.facebook.com/v23.0"

    def self.send_to(phone_number, text)
      token = ENV["WHATSAPP_ACCESS_TOKEN"]
      phone_number_id = ENV["WHATSAPP_BUSINESS_PHONE_NUMBER_ID"]

      if token.blank? || phone_number_id.blank?
        Rails.logger.warn "[ReplySender] WHATSAPP_ACCESS_TOKEN/WHATSAPP_BUSINESS_PHONE_NUMBER_ID missing; reply skipped"
        return false
      end

      uri = URI("#{GRAPH_URL}/#{phone_number_id}/messages")
      payload = {
        messaging_product: "whatsapp",
        to: phone_number,
        type: "text",
        text: { body: text }
      }.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{token}")
      response = http.request(request, payload)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error "[ReplySender] Failed to deliver reply to #{phone_number}: #{response.code} #{response.body}"
        return false
      end
      true
    rescue StandardError => e
      Rails.logger.error "[ReplySender] Error sending reply to #{phone_number}: #{e.message}"
      false
    end
  end
end
